// End-to-end API tests against a real Postgres engine (PGlite, in-process — no install needed).
import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const PORT = 55000 + Math.floor(Math.random() * 5000);
process.env.DATABASE_URL = `postgres://postgres:postgres@127.0.0.1:${PORT}/postgres`;
process.env.PG_POOL_MAX = "1";
process.env.JWT_SECRET = "test-secret-test-secret-test-secret-0123456789";

const { default: app } = await import("../src/index.js");
const { closeDb, db } = await import("../src/lib/db.js");
const { migrate } = await import("../src/lib/migrate.js");

let pg: PGlite;
let server: PGLiteSocketServer;

beforeAll(async () => {
  pg = await PGlite.create();
  server = new PGLiteSocketServer({ db: pg, port: PORT, host: "127.0.0.1" });
  await server.start();
  await migrate(db());
});

afterAll(async () => {
  await closeDb();
  await server.stop();
  await pg.close();
});

// MARK: - Helpers

type Json = any; // eslint-disable-line @typescript-eslint/no-explicit-any

async function call(method: string, path: string, opts: { token?: string; body?: unknown; ip?: string } = {}) {
  const res = await app.request(path, {
    method,
    headers: {
      "Content-Type": "application/json",
      "X-Forwarded-For": opts.ip ?? "10.0.0.1",
      ...(opts.token ? { Authorization: `Bearer ${opts.token}` } : {}),
    },
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
  const text = await res.text();
  return { status: res.status, body: (text ? JSON.parse(text) : null) as Json };
}

async function signup(email: string, displayName = "Admin") {
  const res = await call("POST", "/auth/signup", { body: { email, password: "correct horse", display_name: displayName } });
  expect(res.status).toBe(201);
  return { token: res.body.access_token as string, refresh: res.body.refresh_token as string };
}

async function join(code: string, displayName: string, ip?: string) {
  const res = await call("POST", "/auth/join", { body: { code, display_name: displayName }, ip });
  expect(res.status).toBe(201);
  return { token: res.body.access_token as string, refresh: res.body.refresh_token as string };
}

const prospectBody = (programId: string | null = null) => ({
  first_name: "Léa",
  last_name: "Durand",
  email: "lea@example.com",
  phone: "+33 6 12 34 56 78",
  program_id: programId,
  education_level: "Terminale",
  status: "Curieux",
  notes: "Vient avec ses parents 🙂",
});

// MARK: - Admin accounts

describe("admin accounts", () => {
  it("signs up, logs in, and rejects duplicates and bad passwords", async () => {
    await signup("Owner@Example.com", "Owner");
    const dup = await call("POST", "/auth/signup", { body: { email: "owner@example.com", password: "whatever123", display_name: "X" } });
    expect(dup.status).toBe(409);

    const ok = await call("POST", "/auth/login", { body: { email: "OWNER@example.com", password: "correct horse" } });
    expect(ok.status).toBe(200);
    expect(ok.body.kind).toBe("admin");

    expect((await call("POST", "/auth/login", { body: { email: "owner@example.com", password: "nope" } })).status).toBe(401);
    expect((await call("POST", "/auth/login", { body: { email: "ghost@example.com", password: "nope" } })).status).toBe(401);
    expect((await call("POST", "/auth/signup", { body: { email: "short@example.com", password: "123", display_name: "X" } })).status).toBe(400);
  });

  it("rate-limits failed logins per email", async () => {
    await signup("target@example.com");
    for (let i = 0; i < 10; i++) {
      await call("POST", "/auth/login", { body: { email: "target@example.com", password: "wrong-password" } });
    }
    const res = await call("POST", "/auth/login", { body: { email: "target@example.com", password: "correct horse" } });
    expect(res.status).toBe(429);
  });

  it("rotates refresh tokens and revokes everything on reuse", async () => {
    const s = await signup("rotate@example.com");
    const first = await call("POST", "/auth/refresh", { body: { refresh_token: s.refresh } });
    expect(first.status).toBe(200);
    expect((await call("POST", "/auth/refresh", { body: { refresh_token: s.refresh } })).status).toBe(401);
    expect((await call("POST", "/auth/refresh", { body: { refresh_token: first.body.refresh_token } })).status).toBe(401);
  });

  it("rejects requests without a valid token", async () => {
    expect((await call("GET", "/me")).status).toBe(401);
    expect((await call("GET", "/me", { token: "nope" })).status).toBe(401);
  });
});

// MARK: - Organizations, events, codes

describe("organization with event codes", () => {
  let admin: { token: string };
  let orgId: string;
  let programId: string;
  let event: Json;
  let agent: { token: string; refresh: string };
  let cf: { token: string };

  it("admins create an organization and co-admins join with its admin code", async () => {
    admin = await signup("alice@acme.io", "Alice Martin");
    expect((await call("GET", "/me", { token: admin.token })).body).toMatchObject({ kind: "admin", organizations: [] });

    const created = await call("POST", "/orgs", { token: admin.token, body: { name: "Acme École", event_label: "Salon" } });
    expect(created.status).toBe(201);
    expect(created.body).toMatchObject({ name: "Acme École", event_label: "Salon", role: "admin", display_name: "Alice Martin" });
    expect(created.body.admin_code).toMatch(/^[A-Z2-9]{6}$/);
    orgId = created.body.id;

    const coAdmin = await signup("bob@acme.io", "Bob");
    expect((await call("POST", "/orgs/join", { token: coAdmin.token, body: { admin_code: "WRONG1" } })).status).toBe(401);
    const joined = await call("POST", "/orgs/join", {
      token: coAdmin.token,
      body: { admin_code: created.body.admin_code.toLowerCase() },
    });
    expect(joined.status).toBe(200);
    const admins = await call("GET", `/orgs/${orgId}/admins`, { token: admin.token });
    expect(admins.body.map((a: Json) => a.display_name)).toEqual(["Alice Martin", "Bob"]);
  });

  it("admins create programs and events; events get two join codes", async () => {
    const p = await call("POST", `/orgs/${orgId}/programs`, { token: admin.token, body: { name: "Informatique" } });
    expect(p.status).toBe(201);
    programId = p.body.id;
    expect((await call("POST", `/orgs/${orgId}/programs`, { token: admin.token, body: { name: "Informatique" } })).status).toBe(409);

    const e = await call("POST", `/orgs/${orgId}/events`, { token: admin.token, body: { name: "Salon Novembre", date: "2026-11-14" } });
    expect(e.status).toBe(201);
    expect(e.body).toMatchObject({ date: "2026-11-14", status: "pas_commence", prospect_count: 0 });
    expect(e.body.agent_code).toMatch(/^[A-Z2-9]{6}$/);
    expect(e.body.cf_code).not.toBe(e.body.agent_code);
    event = e.body;
  });

  it("agents and conseillers join an event with a code and a name", async () => {
    expect((await call("POST", "/auth/join", { body: { code: "ZZZZZZ", display_name: "X" } })).status).toBe(401);

    agent = await join(event.agent_code.toLowerCase().replace(/(...)/, "$1-"), "Hugo"); // "abc-def" still works
    cf = await join(event.cf_code, "Claire");

    const me = await call("GET", "/me", { token: agent.token });
    expect(me.body).toMatchObject({
      kind: "participant",
      participant: { display_name: "Hugo", role: "agent" },
      organization: { id: orgId, event_label: "Salon", role: "agent" },
      event: { id: event.id },
    });
    expect(me.body.event.agent_code).toBeUndefined(); // codes are admin-only

    const participants = await call("GET", `/orgs/${orgId}/events/${event.id}/participants`, { token: admin.token });
    expect(participants.body.map((p: Json) => [p.display_name, p.role])).toEqual([
      ["Hugo", "agent"],
      ["Claire", "conseiller_formation"],
    ]);
  });

  it("participants see only their event and cannot administer", async () => {
    const other = await call("POST", `/orgs/${orgId}/events`, { token: admin.token, body: { name: "Autre", date: "2026-12-01" } });
    const visible = await call("GET", `/orgs/${orgId}/events`, { token: agent.token });
    expect(visible.body.map((e: Json) => e.id)).toEqual([event.id]);
    expect(visible.body[0].agent_code).toBeUndefined();

    expect((await call("GET", `/orgs/${orgId}/events/${other.body.id}/prospects`, { token: agent.token })).status).toBe(404);
    expect((await call("POST", `/orgs/${orgId}/events/${other.body.id}/prospects`, { token: agent.token, body: prospectBody() })).status).toBe(404);
    expect((await call("POST", `/orgs/${orgId}/events`, { token: agent.token, body: { name: "X", date: "2026-11-01" } })).status).toBe(403);
    expect((await call("POST", `/orgs/${orgId}/programs`, { token: agent.token, body: { name: "X" } })).status).toBe(403);
    expect((await call("GET", `/orgs/${orgId}/admins`, { token: agent.token })).status).toBe(403);
    expect((await call("POST", "/orgs", { token: agent.token, body: { name: "Mine" } })).status).toBe(403);
    // Admin-created prospect in the other event is invisible to the agent.
    const hidden = await call("POST", `/orgs/${orgId}/events/${other.body.id}/prospects`, { token: admin.token, body: prospectBody() });
    expect((await call("PATCH", `/orgs/${orgId}/prospects/${hidden.body.id}`, { token: agent.token, body: prospectBody() })).status).toBe(404);
  });

  it("agents register prospects; conseillers are read-only", async () => {
    const created = await call("POST", `/orgs/${orgId}/events/${event.id}/prospects`, { token: agent.token, body: prospectBody(programId) });
    expect(created.status).toBe(201);
    expect(created.body).toMatchObject({ first_name: "Léa", created_by_name: "Hugo", program_id: programId });

    expect((await call("POST", `/orgs/${orgId}/events/${event.id}/prospects`, { token: cf.token, body: prospectBody() })).status).toBe(403);
    expect((await call("GET", `/orgs/${orgId}/events/${event.id}/prospects`, { token: cf.token })).body).toHaveLength(1);

    const updated = await call("PATCH", `/orgs/${orgId}/prospects/${created.body.id}`, {
      token: agent.token,
      body: { ...prospectBody(programId), status: "Rdv d'info pris" },
    });
    expect(updated.body.status).toBe("Rdv d'info pris");
    expect((await call("GET", `/orgs/${orgId}/stats/me`, { token: agent.token })).body).toEqual({ prospects: 1, events: 1, rdv: 1 });

    // Renaming yourself updates the author name shown on your prospects.
    await call("PATCH", "/me", { token: agent.token, body: { display_name: "Hugo B." } });
    const list = await call("GET", `/orgs/${orgId}/events/${event.id}/prospects`, { token: admin.token });
    expect(list.body[0].created_by_name).toBe("Hugo B.");

    const archived = await call("POST", `/orgs/${orgId}/prospects/${created.body.id}/archive`, { token: agent.token });
    expect(archived.body.deleted_at).not.toBeNull();
    expect((await call("GET", `/orgs/${orgId}/prospects/archived`, { token: agent.token })).body).toHaveLength(1);
    await call("POST", `/orgs/${orgId}/prospects/${created.body.id}/restore`, { token: agent.token });
  });

  it("registering with the same client id twice creates one prospect", async () => {
    const id = crypto.randomUUID();
    const before = (await call("GET", `/orgs/${orgId}/events/${event.id}/prospects`, { token: admin.token })).body.length;
    const first = await call("POST", `/orgs/${orgId}/events/${event.id}/prospects`, { token: agent.token, body: { ...prospectBody(), id } });
    const retry = await call("POST", `/orgs/${orgId}/events/${event.id}/prospects`, { token: agent.token, body: { ...prospectBody(), id } });
    expect(first.status).toBe(201);
    expect(retry.status).toBe(200);
    expect(retry.body.id).toBe(id);
    const after = (await call("GET", `/orgs/${orgId}/events/${event.id}/prospects`, { token: admin.token })).body.length;
    expect(after).toBe(before + 1);
  });

  it("conseillers pick the programs they follow", async () => {
    await call("PATCH", "/me", { token: cf.token, body: { program_ids: [programId, "00000000-0000-4000-8000-000000000000"] } });
    const participants = await call("GET", `/orgs/${orgId}/events/${event.id}/participants`, { token: admin.token });
    expect(participants.body.find((p: Json) => p.display_name === "Claire").program_ids).toEqual([programId]);
  });

  it("regenerating a code invalidates the old one but keeps people who joined", async () => {
    const regenerated = await call("POST", `/orgs/${orgId}/events/${event.id}/codes`, { token: admin.token, body: { role: "agent" } });
    expect(regenerated.body.agent_code).not.toBe(event.agent_code);
    expect((await call("POST", "/auth/join", { body: { code: event.agent_code, display_name: "Late" } })).status).toBe(401);
    expect((await call("GET", "/me", { token: agent.token })).status).toBe(200);
    event = regenerated.body;
  });

  it("archived events refuse new joins", async () => {
    await call("PATCH", `/orgs/${orgId}/events/${event.id}`, { token: admin.token, body: { is_archived: true } });
    expect((await call("POST", "/auth/join", { body: { code: event.cf_code, display_name: "Late" } })).status).toBe(401);
    await call("PATCH", `/orgs/${orgId}/events/${event.id}`, { token: admin.token, body: { is_archived: false } });
  });

  it("removing a participant ends their access and sessions", async () => {
    const participants = await call("GET", `/orgs/${orgId}/events/${event.id}/participants`, { token: admin.token });
    const hugo = participants.body.find((p: Json) => p.role === "agent");
    expect((await call("DELETE", `/orgs/${orgId}/events/${event.id}/participants/${hugo.id}`, { token: admin.token })).status).toBe(204);
    expect((await call("GET", "/me", { token: agent.token })).status).toBe(401);
    expect((await call("POST", "/auth/refresh", { body: { refresh_token: agent.refresh } })).status).toBe(401);
    // Their prospects stay, still attributed.
    const list = await call("GET", `/orgs/${orgId}/events/${event.id}/prospects`, { token: admin.token });
    expect(list.body[0].created_by_name).toBe("Hugo B.");
  });

  it("isolates organizations from each other", async () => {
    const outsider = await signup("eve@other.org");
    const other = await call("POST", "/orgs", { token: outsider.token, body: { name: "Other" } });
    expect((await call("GET", `/orgs/${orgId}/events`, { token: outsider.token })).status).toBe(404);
    const otherEvent = await call("POST", `/orgs/${other.body.id}/events`, { token: outsider.token, body: { name: "E", date: "2026-12-01" } });
    expect(
      (await call("POST", `/orgs/${other.body.id}/events/${otherEvent.body.id}/prospects`, { token: outsider.token, body: prospectBody(programId) })).status,
    ).toBe(400);
  });

  it("keeps at least one admin", async () => {
    const solo = await signup("solo@example.com");
    const org = await call("POST", "/orgs", { token: solo.token, body: { name: "Solo" } });
    const me = await call("GET", `/orgs/${org.body.id}/admins`, { token: solo.token });
    expect((await call("DELETE", `/orgs/${org.body.id}/admins/${me.body[0].user_id}`, { token: solo.token })).status).toBe(409);
  });

  it("rate-limits code guessing per client", async () => {
    for (let i = 0; i < 20; i++) await call("POST", "/auth/join", { body: { code: "AAAAAA", display_name: "x" }, ip: "10.9.9.9" });
    expect((await call("POST", "/auth/join", { body: { code: event.cf_code, display_name: "x" }, ip: "10.9.9.9" })).status).toBe(429);
    expect((await call("POST", "/auth/join", { body: { code: event.cf_code, display_name: "x" }, ip: "10.9.9.10" })).status).toBe(201);
  });

  it("deleting a program detaches it everywhere", async () => {
    await call("PATCH", `/orgs/${orgId}/events/${event.id}`, { token: admin.token, body: { program_objectives: { [programId]: 5 } } });
    expect((await call("DELETE", `/orgs/${orgId}/programs/${programId}`, { token: admin.token })).status).toBe(204);
    const list = await call("GET", `/orgs/${orgId}/events/${event.id}/prospects`, { token: admin.token });
    expect(list.body[0].program_id).toBeNull();
    const events = await call("GET", `/orgs/${orgId}/events`, { token: admin.token });
    expect(events.body.find((e: Json) => e.id === event.id).program_objectives).toEqual({});
  });
});
