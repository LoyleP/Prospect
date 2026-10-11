import { Hono } from "hono";
import type postgres from "postgres";
import { z } from "zod";
import { type AppEnv, assertRole, requireAdminAccount, requireMember, uuidParam } from "../lib/context.js";
import { db } from "../lib/db.js";
import { apiError, forbidden, notFound, parseBody } from "../lib/errors.js";
import { isRateLimited, normalizeCode, recordFailure, uniqueJoinCode } from "../lib/tokens.js";
import { events } from "./events.js";

/** An organization as seen by one admin (`o` = organizations). */
const adminOrgColumns = (sql: postgres.Sql, displayName: string) => sql`
  o.id, o.name, o.event_label, o.admin_code, o.created_at,
  'admin' as role, ${displayName}::text as display_name, '{}'::uuid[] as program_ids`;

// Palette cycled for new programs when the client doesn't pick a colour.
const PROGRAM_COLORS = [
  "#3366E6", "#2EC7BF", "#9440D9", "#F2D11A", "#F28019",
  "#33B859", "#142E8C", "#66B8F2", "#99E08C", "#FAED8C",
];

const name = z.string().trim().min(1).max(120);
const hexColor = z.string().regex(/^#[0-9A-Fa-f]{6}$/);

export const orgs = new Hono<AppEnv>();

// MARK: - Organizations (admin accounts only)

orgs.post("/", requireAdminAccount, async (c) => {
  const caller = c.get("caller");
  if (caller.kind !== "admin") throw forbidden();
  const body = await parseBody(c.req, z.object({ name, event_label: name.optional() }));
  const adminCode = await uniqueJoinCode();
  const sql = db();
  const orgId = await sql.begin(async (tx) => {
    const [o] = await tx<{ id: string }[]>`
      insert into organizations (name, event_label, admin_code)
      values (${body.name}, ${body.event_label ?? "Événement"}, ${adminCode})
      returning id`;
    await tx`insert into memberships (org_id, user_id, last_seen_at) values (${o!.id}, ${caller.userId}, now())`;
    return o!.id;
  });
  const [row] = await sql`select ${adminOrgColumns(sql, caller.displayName)} from organizations o where o.id = ${orgId}`;
  return c.json(row, 201);
});

/** Joins an existing organization as co-admin with its admin code. */
orgs.post("/join", requireAdminAccount, async (c) => {
  const caller = c.get("caller");
  if (caller.kind !== "admin") throw forbidden();
  const body = await parseBody(c.req, z.object({ admin_code: z.string().trim().min(1).max(20) }));
  const limitKey = `admin-join:${caller.userId}`;
  if (await isRateLimited(limitKey, 10, 15)) {
    throw apiError(429, "too_many_requests", "Too many attempts. Try again in a few minutes.");
  }
  const sql = db();
  const [org] = await sql<{ id: string }[]>`select id from organizations where admin_code = ${normalizeCode(body.admin_code)}`;
  if (!org) {
    await recordFailure(limitKey);
    throw apiError(401, "invalid_code", "This admin code is invalid");
  }
  await sql`
    insert into memberships (org_id, user_id, last_seen_at) values (${org.id}, ${caller.userId}, now())
    on conflict do nothing`;
  const [row] = await sql`select ${adminOrgColumns(sql, caller.displayName)} from organizations o where o.id = ${org.id}`;
  return c.json(row);
});

orgs.use("/:orgId", requireMember);
orgs.use("/:orgId/*", requireMember);

orgs.get("/:orgId", async (c) => {
  const m = c.get("membership");
  const sql = db();
  if (m.role === "admin") {
    const [row] = await sql`select ${adminOrgColumns(sql, m.displayName)} from organizations o where o.id = ${m.orgId}`;
    return c.json(row);
  }
  const [row] = await sql`select id, name, event_label, created_at from organizations where id = ${m.orgId}`;
  return c.json({ ...row, role: m.role, display_name: m.displayName, program_ids: [] });
});

orgs.patch("/:orgId", async (c) => {
  const m = assertRole(c, "admin");
  const body = await parseBody(c.req, z.object({ name: name.optional(), event_label: name.optional() }));
  const sql = db();
  const [row] = await sql`
    update organizations as o set
      name        = coalesce(${body.name ?? null}, o.name),
      event_label = coalesce(${body.event_label ?? null}, o.event_label)
    where o.id = ${m.orgId}
    returning ${adminOrgColumns(sql, m.displayName)}`;
  return c.json(row);
});

/** Replaces the admin code; the old one stops working immediately. */
orgs.post("/:orgId/admin-code", async (c) => {
  const m = assertRole(c, "admin");
  const code = await uniqueJoinCode();
  const sql = db();
  const [row] = await sql`
    update organizations as o set admin_code = ${code} where o.id = ${m.orgId}
    returning ${adminOrgColumns(sql, m.displayName)}`;
  return c.json(row);
});

// MARK: - Admins

orgs.get("/:orgId/admins", async (c) => {
  const { orgId } = assertRole(c, "admin");
  return c.json(await db()`
    select u.id as user_id, u.email, u.display_name, m.last_seen_at, m.created_at
    from memberships m join users u on u.id = m.user_id
    where m.org_id = ${orgId}
    order by u.display_name`);
});

/** Removes an admin, or yourself (leaving). The last admin can't be removed. */
orgs.delete("/:orgId/admins/:userId", async (c) => {
  const { orgId } = assertRole(c, "admin");
  const userId = uuidParam(c, "userId");
  const sql = db();
  const [target] = await sql`select 1 from memberships where org_id = ${orgId} and user_id = ${userId}`;
  if (!target) throw notFound("Admin");
  const [{ n } = { n: 0 }] = await sql<{ n: number }[]>`select count(*)::int as n from memberships where org_id = ${orgId}`;
  if (n <= 1) throw apiError(409, "last_admin", "An organization needs at least one admin");
  await sql`delete from memberships where org_id = ${orgId} and user_id = ${userId}`;
  return c.body(null, 204);
});

// MARK: - Programs

orgs.get("/:orgId/programs", async (c) => {
  const { orgId } = c.get("membership");
  return c.json(await db()`
    select id, name, color, sort_order from programs where org_id = ${orgId} order by sort_order, name`);
});

orgs.post("/:orgId/programs", async (c) => {
  const { orgId } = assertRole(c, "admin");
  const body = await parseBody(c.req, z.object({ name, color: hexColor.optional() }));
  const sql = db();
  const [{ n } = { n: 0 }] = await sql<{ n: number }[]>`select count(*)::int as n from programs where org_id = ${orgId}`;
  const [row] = await sql`
    insert into programs (org_id, name, color, sort_order)
    values (${orgId}, ${body.name}, ${body.color ?? PROGRAM_COLORS[n % PROGRAM_COLORS.length]!}, ${n})
    returning id, name, color, sort_order`;
  return c.json(row, 201);
});

orgs.patch("/:orgId/programs/:programId", async (c) => {
  const { orgId } = assertRole(c, "admin");
  const programId = uuidParam(c, "programId");
  const body = await parseBody(
    c.req,
    z.object({ name: name.optional(), color: hexColor.optional(), sort_order: z.number().int().min(0).optional() }),
  );
  const [row] = await db()`
    update programs set
      name       = coalesce(${body.name ?? null}, name),
      color      = coalesce(${body.color ?? null}, color),
      sort_order = coalesce(${body.sort_order ?? null}, sort_order)
    where id = ${programId} and org_id = ${orgId}
    returning id, name, color, sort_order`;
  if (!row) throw notFound("Program");
  return c.json(row);
});

/** Deletes a program. Its prospects keep existing with no program. */
orgs.delete("/:orgId/programs/:programId", async (c) => {
  const { orgId } = assertRole(c, "admin");
  const programId = uuidParam(c, "programId");
  const deleted = await db().begin(async (tx) => {
    const res = await tx`delete from programs where id = ${programId} and org_id = ${orgId}`;
    if (res.count === 0) return false;
    await tx`update participants set program_ids = array_remove(program_ids, ${programId}::uuid) where org_id = ${orgId}`;
    await tx`update events set program_objectives = program_objectives - ${programId}::text where org_id = ${orgId}`;
    return true;
  });
  if (!deleted) throw notFound("Program");
  return c.body(null, 204);
});

orgs.route("/:orgId", events);
