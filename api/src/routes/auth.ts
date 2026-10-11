import type { Context } from "hono";
import { Hono } from "hono";
import { z } from "zod";
import type { AppEnv, ParticipantRole } from "../lib/context.js";
import { db } from "../lib/db.js";
import { apiError, parseBody } from "../lib/errors.js";
import {
  consumeRefreshToken,
  DUMMY_PASSWORD_HASH,
  hashPassword,
  isRateLimited,
  issueRefreshToken,
  normalizeCode,
  type Principal,
  recordFailure,
  revokeRefreshToken,
  signAccessToken,
  verifyPassword,
} from "../lib/tokens.js";

// Failed attempts allowed per window before answering 429.
const MAX_LOGIN_FAILURES = 10;   // per email
const MAX_JOIN_FAILURES = 20;    // per client IP — codes are 6 chars from a 31-char alphabet
const FAILURE_WINDOW_MINUTES = 15;

const emailSchema = z.string().trim().toLowerCase().pipe(z.email()).pipe(z.string().max(254));
const passwordSchema = z.string().min(8, "at least 8 characters").max(200);
const nameSchema = z.string().trim().min(1).max(80);

async function sessionFor(principal: Principal) {
  const access = await signAccessToken(principal);
  return {
    access_token: access.token,
    refresh_token: await issueRefreshToken(principal),
    expires_at: access.expiresAt,
    kind: principal.kind,
  };
}

/** Best-effort client IP behind Vercel's proxy. */
function clientIp(c: Context): string {
  return c.req.header("x-forwarded-for")?.split(",")[0]?.trim() || c.req.header("x-real-ip") || "unknown";
}

export const auth = new Hono<AppEnv>();

/** Creates an admin account. No email verification by design. */
auth.post("/signup", async (c) => {
  const body = await parseBody(
    c.req,
    z.object({ email: emailSchema, password: passwordSchema, display_name: nameSchema }),
  );
  const [user] = await db()<{ id: string }[]>`
    insert into users (email, display_name, password_hash)
    values (${body.email}, ${body.display_name}, ${await hashPassword(body.password)})
    on conflict (email) do nothing
    returning id`;
  if (!user) throw apiError(409, "email_taken", "An account already exists for this email");
  return c.json(await sessionFor({ kind: "admin", userId: user.id }), 201);
});

auth.post("/login", async (c) => {
  const body = await parseBody(c.req, z.object({ email: emailSchema, password: z.string().min(1).max(200) }));
  const limitKey = `login:${body.email}`;
  if (await isRateLimited(limitKey, MAX_LOGIN_FAILURES, FAILURE_WINDOW_MINUTES)) {
    throw apiError(429, "too_many_requests", "Too many attempts. Try again in a few minutes.");
  }
  const [user] = await db()<{ id: string; password_hash: string }[]>`
    select id, password_hash from users where email = ${body.email}`;
  const ok = await verifyPassword(body.password, user?.password_hash ?? DUMMY_PASSWORD_HASH);
  if (!user || !ok) {
    await recordFailure(limitKey);
    throw apiError(401, "invalid_credentials", "Incorrect email or password");
  }
  return c.json(await sessionFor({ kind: "admin", userId: user.id }));
});

/** Joins an event with its agent or conseiller code. No account needed. */
auth.post("/join", async (c) => {
  const body = await parseBody(c.req, z.object({ code: z.string().trim().min(1).max(20), display_name: nameSchema }));
  const limitKey = `join:${clientIp(c)}`;
  if (await isRateLimited(limitKey, MAX_JOIN_FAILURES, FAILURE_WINDOW_MINUTES)) {
    throw apiError(429, "too_many_requests", "Too many attempts. Try again in a few minutes.");
  }
  const code = normalizeCode(body.code);
  const sql = db();
  const [event] = await sql<{ id: string; org_id: string; role: ParticipantRole }[]>`
    select id, org_id,
           case when agent_code = ${code} then 'agent' else 'conseiller_formation' end as role
    from events
    where (agent_code = ${code} or cf_code = ${code}) and not is_archived`;
  if (!event) {
    await recordFailure(limitKey);
    throw apiError(401, "invalid_code", "This code is invalid or the event is closed");
  }
  const [participant] = await sql<{ id: string }[]>`
    insert into participants (org_id, event_id, role, display_name, last_seen_at)
    values (${event.org_id}, ${event.id}, ${event.role}, ${body.display_name}, now())
    returning id`;
  return c.json(await sessionFor({ kind: "participant", participantId: participant!.id }), 201);
});

auth.post("/refresh", async (c) => {
  const { refresh_token } = await parseBody(c.req, z.object({ refresh_token: z.string().min(1) }));
  const principal = await consumeRefreshToken(refresh_token);
  if (!principal) throw apiError(401, "invalid_refresh_token", "Session expired, please sign in again");
  if (principal.kind === "participant") {
    const [active] = await db()`select 1 from participants where id = ${principal.participantId} and revoked_at is null`;
    if (!active) throw apiError(401, "invalid_refresh_token", "You were removed from this event");
  }
  return c.json(await sessionFor(principal));
});

auth.post("/logout", async (c) => {
  const { refresh_token } = await parseBody(c.req, z.object({ refresh_token: z.string().min(1) }));
  await revokeRefreshToken(refresh_token);
  return c.body(null, 204);
});
