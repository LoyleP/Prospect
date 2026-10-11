import type { Context, MiddlewareHandler } from "hono";
import { db } from "./db.js";
import { apiError, forbidden, notFound } from "./errors.js";
import { verifyAccessToken } from "./tokens.js";

export type Role = "agent" | "conseiller_formation" | "admin";
export type ParticipantRole = Exclude<Role, "admin">;

export type Caller =
  | { kind: "admin"; userId: string; email: string; displayName: string }
  | {
      kind: "participant";
      participantId: string;
      orgId: string;
      eventId: string;
      role: ParticipantRole;
      displayName: string;
    };

/** The caller's access within the organization of the current `/orgs/:orgId` request. */
export interface Membership {
  orgId: string;
  role: Role;
  displayName: string;
  /** Set for participants: the only event they may see. */
  eventId: string | null;
}

export type AppEnv = {
  Variables: {
    caller: Caller;
    membership: Membership;
  };
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isUuid = (v: string | undefined): v is string => !!v && UUID_RE.test(v);

/** Reads a uuid path parameter, answering 404 for anything malformed. */
export function uuidParam(c: Context, name: string): string {
  const v = c.req.param(name);
  if (!isUuid(v)) throw notFound();
  return v;
}

const unauthorized = () => apiError(401, "unauthorized", "Missing or expired access token");

/** Authenticates the bearer token. Removed participants and deleted accounts are rejected here. */
export const requireUser: MiddlewareHandler<AppEnv> = async (c, next) => {
  const header = c.req.header("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  const principal = token ? await verifyAccessToken(token) : null;
  if (!principal) throw unauthorized();

  const sql = db();
  if (principal.kind === "admin") {
    const [u] = await sql<{ email: string; display_name: string }[]>`
      select email, display_name from users where id = ${principal.userId}`;
    if (!u) throw unauthorized();
    c.set("caller", { kind: "admin", userId: principal.userId, email: u.email, displayName: u.display_name });
  } else {
    const [p] = await sql<{ org_id: string; event_id: string; role: ParticipantRole; display_name: string }[]>`
      update participants set last_seen_at = now()
      where id = ${principal.participantId} and revoked_at is null
      returning org_id, event_id, role, display_name`;
    if (!p) throw unauthorized();
    c.set("caller", {
      kind: "participant",
      participantId: principal.participantId,
      orgId: p.org_id,
      eventId: p.event_id,
      role: p.role,
      displayName: p.display_name,
    });
  }
  await next();
};

export const requireAdminAccount: MiddlewareHandler<AppEnv> = async (c, next) => {
  if (c.get("caller").kind !== "admin") throw forbidden();
  await next();
};

/** Resolves the caller's access to `:orgId`. Outsiders get a 404, not a 403, so org ids don't leak. */
export const requireMember: MiddlewareHandler<AppEnv> = async (c, next) => {
  const orgId = uuidParam(c, "orgId");
  const caller = c.get("caller");
  if (caller.kind === "participant") {
    if (caller.orgId !== orgId) throw notFound("Organization");
    c.set("membership", { orgId, role: caller.role, displayName: caller.displayName, eventId: caller.eventId });
  } else {
    const [m] = await db()`select 1 from memberships where org_id = ${orgId} and user_id = ${caller.userId}`;
    if (!m) throw notFound("Organization");
    c.set("membership", { orgId, role: "admin", displayName: caller.displayName, eventId: null });
  }
  await next();
};

export function assertRole(c: Context<AppEnv>, ...allowed: Role[]): Membership {
  const m = c.get("membership");
  if (!allowed.includes(m.role)) throw forbidden();
  return m;
}

/** Participants may only touch their own event; admins any event of the organization. */
export function assertEventAccess(c: Context<AppEnv>, eventId: string): void {
  const m = c.get("membership");
  if (m.eventId && m.eventId !== eventId) throw notFound("Event");
}

/** The author columns for a prospect created by this caller. */
export function authorOf(c: Context<AppEnv>): { userId: string | null; participantId: string | null; name: string } {
  const caller = c.get("caller");
  return caller.kind === "admin"
    ? { userId: caller.userId, participantId: null, name: caller.displayName }
    : { userId: null, participantId: caller.participantId, name: caller.displayName };
}
