import { Hono } from "hono";
import type postgres from "postgres";
import { z } from "zod";
import { type AppEnv, assertEventAccess, assertRole, authorOf, uuidParam } from "../lib/context.js";
import { db } from "../lib/db.js";
import { apiError, notFound, parseBody } from "../lib/errors.js";
import { uniqueJoinCode } from "../lib/tokens.js";

const EVENT_STATUSES = ["pas_commence", "en_cours", "termine"] as const;
export const PROSPECT_STATUSES = ["Curieux", "Intéressé", "Rdv d'info pris", "Rdv d'admission pris"] as const;
const RDV_STATUSES = ["Rdv d'info pris", "Rdv d'admission pris"];

/** Event columns safe for everyone (`e` = events). Join codes are added for admins only. */
export const eventColumns = (sql: postgres.Sql) => sql`
  e.id, e.name, e.date, e.status, e.is_archived, e.pre_registered,
  e.rdv_target_low, e.rdv_target_high, e.program_objectives, e.created_at`;

const prospectCount = (sql: postgres.Sql) => sql`
  (select count(*)::int from prospects p where p.event_id = e.id and p.deleted_at is null) as prospect_count`;

const prospectColumns = (sql: postgres.Sql) => sql`
  p.id, p.event_id, p.first_name, p.last_name, p.email, p.phone, p.program_id,
  p.education_level, p.status, p.notes,
  coalesce(p.created_by_user, p.created_by_participant) as created_by,
  coalesce(u.display_name, pa.display_name, p.created_by_name) as created_by_name,
  p.created_at, p.updated_at, p.deleted_at`;

/** Prospect rows joined to their author, for an up-to-date name. */
const prospectSource = (sql: postgres.Sql) => sql`
  prospects p
  left join users u on u.id = p.created_by_user
  left join participants pa on pa.id = p.created_by_participant`;

const participantColumns = (sql: postgres.Sql) => sql`
  id, display_name, role, program_ids, last_seen_at, created_at`;

const text = (max: number) => z.string().trim().min(1).max(max);
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "expected YYYY-MM-DD");
const count = z.number().int().min(0).max(1_000_000);

const prospectFields = {
  first_name: text(120),
  last_name: text(120),
  email: z.string().trim().max(254).pipe(z.email()),
  phone: z.string().trim().min(6).max(40).regex(/^[0-9 +\-()/.]+$/, "invalid phone number"),
  program_id: z.uuid().nullable(),
  education_level: text(80),
  status: z.enum(PROSPECT_STATUSES),
  notes: z.string().trim().max(5000).nullable().optional(),
};

async function assertProgramInOrg(sql: postgres.Sql, orgId: string, programId: string | null): Promise<void> {
  if (!programId) return;
  const [p] = await sql`select 1 from programs where id = ${programId} and org_id = ${orgId}`;
  if (!p) throw apiError(400, "invalid_request", "program_id: unknown program");
}

async function loadProspect(sql: postgres.Sql, orgId: string, id: string) {
  const [row] = await sql`
    select ${prospectColumns(sql)} from ${prospectSource(sql)}
    where p.id = ${id} and p.org_id = ${orgId}`;
  if (!row) throw notFound("Prospect");
  return row;
}

/** Loads an event of the org the caller may access, or answers 404. */
async function loadEvent(c: Parameters<typeof assertEventAccess>[0], eventId: string) {
  const { orgId } = c.get("membership");
  assertEventAccess(c, eventId);
  const [event] = await db()<{ is_archived: boolean }[]>`
    select is_archived from events where id = ${eventId} and org_id = ${orgId}`;
  if (!event) throw notFound("Event");
  return event;
}

/** Checks the prospect is in the caller's reach (their event, for participants). */
async function assertProspectAccess(c: Parameters<typeof assertEventAccess>[0], id: string): Promise<void> {
  const { orgId } = c.get("membership");
  const [row] = await db()<{ event_id: string }[]>`select event_id from prospects where id = ${id} and org_id = ${orgId}`;
  if (!row) throw notFound("Prospect");
  assertEventAccess(c, row.event_id);
}

export const events = new Hono<AppEnv>();

// MARK: - Events

/** Admins: every event with its join codes. Participants: only their own event. */
events.get("/events", async (c) => {
  const { orgId, eventId, role } = c.get("membership");
  const sql = db();
  const codes = role === "admin" ? sql`, e.agent_code, e.cf_code` : sql``;
  return c.json(await sql`
    select ${eventColumns(sql)}, ${prospectCount(sql)} ${codes}
    from events e
    where e.org_id = ${orgId} ${eventId ? sql`and e.id = ${eventId}` : sql``}
    order by e.date desc, e.created_at desc`);
});

events.post("/events", async (c) => {
  const { orgId } = assertRole(c, "admin");
  const body = await parseBody(c.req, z.object({ name: text(120), date }));
  const sql = db();
  const agentCode = await uniqueJoinCode();
  let cfCode = await uniqueJoinCode();
  while (cfCode === agentCode) cfCode = await uniqueJoinCode();
  const [row] = await sql`
    insert into events as e (org_id, name, date, agent_code, cf_code)
    values (${orgId}, ${body.name}, ${body.date}, ${agentCode}, ${cfCode})
    returning ${eventColumns(sql)}, 0 as prospect_count, e.agent_code, e.cf_code`;
  return c.json(row, 201);
});

events.patch("/events/:eventId", async (c) => {
  const { orgId } = assertRole(c, "admin");
  const eventId = uuidParam(c, "eventId");
  const b = await parseBody(
    c.req,
    z.object({
      name: text(120).optional(),
      date: date.optional(),
      status: z.enum(EVENT_STATUSES).optional(),
      is_archived: z.boolean().optional(),
      pre_registered: count.optional(),
      rdv_target_low: count.optional(),
      rdv_target_high: count.optional(),
      program_objectives: z.record(z.uuid(), count).optional(),
    }),
  );
  const sql = db();
  const [row] = await sql`
    update events as e set
      name               = coalesce(${b.name ?? null}, e.name),
      date               = coalesce(${b.date ?? null}::date, e.date),
      status             = coalesce(${b.status ?? null}, e.status),
      is_archived        = coalesce(${b.is_archived ?? null}::boolean, e.is_archived),
      pre_registered     = coalesce(${b.pre_registered ?? null}::int, e.pre_registered),
      rdv_target_low     = coalesce(${b.rdv_target_low ?? null}::int, e.rdv_target_low),
      rdv_target_high    = coalesce(${b.rdv_target_high ?? null}::int, e.rdv_target_high),
      program_objectives = coalesce(${b.program_objectives ? sql.json(b.program_objectives) : null}::jsonb, e.program_objectives)
    where e.id = ${eventId} and e.org_id = ${orgId}
    returning ${eventColumns(sql)}, ${prospectCount(sql)}, e.agent_code, e.cf_code`;
  if (!row) throw notFound("Event");
  return c.json(row);
});

events.delete("/events/:eventId", async (c) => {
  const { orgId } = assertRole(c, "admin");
  const eventId = uuidParam(c, "eventId");
  const res = await db()`delete from events where id = ${eventId} and org_id = ${orgId}`;
  if (res.count === 0) throw notFound("Event");
  return c.body(null, 204);
});

/** Replaces one join code. People who already joined stay; the old code stops working. */
events.post("/events/:eventId/codes", async (c) => {
  const { orgId } = assertRole(c, "admin");
  const eventId = uuidParam(c, "eventId");
  const { role } = await parseBody(c.req, z.object({ role: z.enum(["agent", "conseiller_formation"]) }));
  const code = await uniqueJoinCode();
  const sql = db();
  const column = role === "agent" ? sql`agent_code` : sql`cf_code`;
  const [row] = await sql`
    update events as e set ${column} = ${code}
    where e.id = ${eventId} and e.org_id = ${orgId}
    returning ${eventColumns(sql)}, ${prospectCount(sql)}, e.agent_code, e.cf_code`;
  if (!row) throw notFound("Event");
  return c.json(row);
});

// MARK: - Participants

events.get("/events/:eventId/participants", async (c) => {
  const { orgId } = assertRole(c, "admin");
  const eventId = uuidParam(c, "eventId");
  const sql = db();
  return c.json(await sql`
    select ${participantColumns(sql)} from participants
    where event_id = ${eventId} and org_id = ${orgId} and revoked_at is null
    order by role, display_name`);
});

/** Removes someone from an event: their sessions end on their next request. */
events.delete("/events/:eventId/participants/:participantId", async (c) => {
  const { orgId } = assertRole(c, "admin");
  const eventId = uuidParam(c, "eventId");
  const participantId = uuidParam(c, "participantId");
  const sql = db();
  const res = await sql`
    update participants set revoked_at = now()
    where id = ${participantId} and event_id = ${eventId} and org_id = ${orgId} and revoked_at is null`;
  if (res.count === 0) throw notFound("Participant");
  await sql`update refresh_tokens set revoked_at = now() where participant_id = ${participantId} and revoked_at is null`;
  return c.body(null, 204);
});

// MARK: - Prospects

/** Active prospects of one event, newest first. Polled by the app while the list is open. */
events.get("/events/:eventId/prospects", async (c) => {
  const eventId = uuidParam(c, "eventId");
  await loadEvent(c, eventId);
  const sql = db();
  return c.json(await sql`
    select ${prospectColumns(sql)} from ${prospectSource(sql)}
    where p.event_id = ${eventId} and p.deleted_at is null
    order by p.created_at desc`);
});

events.post("/events/:eventId/prospects", async (c) => {
  const { orgId } = assertRole(c, "agent", "admin");
  const eventId = uuidParam(c, "eventId");
  const event = await loadEvent(c, eventId);
  if (event.is_archived) throw apiError(409, "event_archived", "This event is archived");
  // `id` is optional and chosen by the client: sending the same one again returns the existing
  // prospect instead of creating a duplicate, so a retry after a network drop is safe.
  const b = await parseBody(c.req, z.object({ ...prospectFields, id: z.uuid().optional() }));
  const sql = db();
  await assertProgramInOrg(sql, orgId, b.program_id);
  const author = authorOf(c);
  const id = b.id ?? crypto.randomUUID();
  const [created] = await sql<{ id: string }[]>`
    insert into prospects (id, org_id, event_id, first_name, last_name, email, phone, program_id, education_level,
                           status, notes, created_by_user, created_by_participant, created_by_name)
    values (${id}, ${orgId}, ${eventId}, ${b.first_name}, ${b.last_name}, ${b.email}, ${b.phone}, ${b.program_id},
            ${b.education_level}, ${b.status}, ${b.notes ?? null}, ${author.userId}, ${author.participantId}, ${author.name})
    on conflict (id) do nothing
    returning id`;
  return c.json(await loadProspect(sql, orgId, id), created ? 201 : 200);
});

/** Archived prospects: the whole organization for admins, their event for participants. */
events.get("/prospects/archived", async (c) => {
  const { orgId, eventId } = c.get("membership");
  const sql = db();
  return c.json(await sql`
    select ${prospectColumns(sql)} from ${prospectSource(sql)}
    where p.org_id = ${orgId} and p.deleted_at is not null
      ${eventId ? sql`and p.event_id = ${eventId}` : sql``}
    order by p.deleted_at desc`);
});

events.patch("/prospects/:prospectId", async (c) => {
  const { orgId } = assertRole(c, "agent", "admin");
  const id = uuidParam(c, "prospectId");
  await assertProspectAccess(c, id);
  const b = await parseBody(c.req, z.object(prospectFields));
  const sql = db();
  await assertProgramInOrg(sql, orgId, b.program_id);
  await sql`
    update prospects set
      first_name = ${b.first_name}, last_name = ${b.last_name}, email = ${b.email}, phone = ${b.phone},
      program_id = ${b.program_id}, education_level = ${b.education_level}, status = ${b.status},
      notes = ${b.notes ?? null}, updated_at = now()
    where id = ${id} and org_id = ${orgId}`;
  return c.json(await loadProspect(sql, orgId, id));
});

events.post("/prospects/:prospectId/archive", async (c) => {
  const { orgId } = assertRole(c, "agent", "admin");
  const id = uuidParam(c, "prospectId");
  await assertProspectAccess(c, id);
  const sql = db();
  await sql`update prospects set deleted_at = coalesce(deleted_at, now()) where id = ${id} and org_id = ${orgId}`;
  return c.json(await loadProspect(sql, orgId, id));
});

events.post("/prospects/:prospectId/restore", async (c) => {
  const { orgId } = assertRole(c, "agent", "admin");
  const id = uuidParam(c, "prospectId");
  await assertProspectAccess(c, id);
  const sql = db();
  await sql`update prospects set deleted_at = null where id = ${id} and org_id = ${orgId}`;
  return c.json(await loadProspect(sql, orgId, id));
});

/** Permanent delete — admins only, not exposed in the app UI. */
events.delete("/prospects/:prospectId", async (c) => {
  const { orgId } = assertRole(c, "admin");
  const id = uuidParam(c, "prospectId");
  const res = await db()`delete from prospects where id = ${id} and org_id = ${orgId}`;
  if (res.count === 0) throw notFound("Prospect");
  return c.body(null, 204);
});

// MARK: - Stats

/** The caller's own totals in this organization (profile screen). */
events.get("/stats/me", async (c) => {
  const { orgId } = c.get("membership");
  const author = authorOf(c);
  const sql = db();
  const [row] = await sql`
    select count(*)::int as prospects,
           count(distinct event_id)::int as events,
           count(*) filter (where status = any(${RDV_STATUSES}))::int as rdv
    from prospects
    where org_id = ${orgId} and deleted_at is null
      and ${author.userId ? sql`created_by_user = ${author.userId}` : sql`created_by_participant = ${author.participantId}`}`;
  return c.json(row);
});
