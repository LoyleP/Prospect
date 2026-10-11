import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv } from "../lib/context.js";
import { db } from "../lib/db.js";
import { parseBody } from "../lib/errors.js";
import { eventColumns } from "./events.js";

export const me = new Hono<AppEnv>();

/**
 * Admin: the account and every organization it administers.
 * Participant: their event, its organization, and their own profile.
 */
me.get("/", async (c) => {
  const caller = c.get("caller");
  const sql = db();

  if (caller.kind === "admin") {
    const organizations = await sql`
      update memberships m set last_seen_at = now()
      from organizations o
      where o.id = m.org_id and m.user_id = ${caller.userId}
      returning o.id, o.name, o.event_label, o.admin_code, o.created_at,
                'admin' as role, ${caller.displayName}::text as display_name, '{}'::uuid[] as program_ids`;
    organizations.sort((a, b) => String(a.name).localeCompare(String(b.name)));
    return c.json({
      kind: "admin",
      user: { id: caller.userId, email: caller.email, display_name: caller.displayName },
      organizations,
    });
  }

  const [row] = await sql`
    select p.program_ids, o.id as org_id, o.name as org_name, o.event_label, o.created_at as org_created_at
    from participants p join organizations o on o.id = p.org_id
    where p.id = ${caller.participantId}`;
  const [event] = await sql`
    select ${eventColumns(sql)},
      (select count(*)::int from prospects p where p.event_id = e.id and p.deleted_at is null) as prospect_count
    from events e where e.id = ${caller.eventId}`;
  return c.json({
    kind: "participant",
    participant: { id: caller.participantId, display_name: caller.displayName, role: caller.role },
    organization: {
      id: row!.org_id,
      name: row!.org_name,
      event_label: row!.event_label,
      created_at: row!.org_created_at,
      role: caller.role,
      display_name: caller.displayName,
      program_ids: row!.program_ids,
    },
    event,
  });
});

/** Edit your own display name (and, for participants, the programs you follow). */
me.patch("/", async (c) => {
  const caller = c.get("caller");
  const body = await parseBody(
    c.req,
    z.object({
      display_name: z.string().trim().min(1).max(80).optional(),
      program_ids: z.array(z.uuid()).max(200).optional(),
    }),
  );
  const sql = db();
  if (caller.kind === "admin") {
    if (body.display_name) await sql`update users set display_name = ${body.display_name} where id = ${caller.userId}`;
  } else {
    const programIds = body.program_ids
      ? (await sql<{ id: string }[]>`
          select id from programs where org_id = ${caller.orgId} and id = any(${body.program_ids}::uuid[])`).map((r) => r.id)
      : null;
    await sql`
      update participants set
        display_name = coalesce(${body.display_name ?? null}, display_name),
        program_ids  = coalesce(${programIds}::uuid[], program_ids)
      where id = ${caller.participantId}`;
  }
  return c.body(null, 204);
});
