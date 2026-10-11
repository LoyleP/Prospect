import { createHash, randomBytes, randomInt, scrypt, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";
import { jwtVerify, SignJWT } from "jose";
import { db } from "./db.js";

const scryptAsync = promisify(scrypt) as (password: string, salt: Buffer, keylen: number) => Promise<Buffer>;

const ISSUER = "prospect-api";
export const ACCESS_TOKEN_TTL_SECONDS = 60 * 60; // 1 hour
const REFRESH_TOKEN_TTL_DAYS = 60;

function secret(): string {
  const s = process.env.JWT_SECRET;
  if (!s || s.length < 32) throw new Error("JWT_SECRET must be set to at least 32 characters");
  return s;
}

const key = () => new TextEncoder().encode(secret());

/** Who is calling: an admin account, or a participant of one event. */
export type Principal =
  | { kind: "admin"; userId: string }
  | { kind: "participant"; participantId: string };

const subjectOf = (p: Principal) => (p.kind === "admin" ? p.userId : p.participantId);

export async function signAccessToken(principal: Principal): Promise<{ token: string; expiresAt: number }> {
  const expiresAt = Math.floor(Date.now() / 1000) + ACCESS_TOKEN_TTL_SECONDS;
  const token = await new SignJWT({ kind: principal.kind })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(subjectOf(principal))
    .setIssuer(ISSUER)
    .setIssuedAt()
    .setExpirationTime(expiresAt)
    .sign(key());
  return { token, expiresAt };
}

/** Returns the principal, or null for any invalid/expired token. */
export async function verifyAccessToken(token: string): Promise<Principal | null> {
  try {
    const { payload } = await jwtVerify(token, key(), { issuer: ISSUER, algorithms: ["HS256"] });
    if (typeof payload.sub !== "string") return null;
    if (payload.kind === "admin") return { kind: "admin", userId: payload.sub };
    if (payload.kind === "participant") return { kind: "participant", participantId: payload.sub };
    return null;
  } catch {
    return null;
  }
}

const sha256 = (value: string) => createHash("sha256").update(value).digest("hex");

export async function issueRefreshToken(principal: Principal): Promise<string> {
  const token = randomBytes(32).toString("base64url");
  const userId = principal.kind === "admin" ? principal.userId : null;
  const participantId = principal.kind === "participant" ? principal.participantId : null;
  await db()`
    insert into refresh_tokens (user_id, participant_id, token_hash, expires_at)
    values (${userId}, ${participantId}, ${sha256(token)}, now() + make_interval(days => ${REFRESH_TOKEN_TTL_DAYS}))`;
  return token;
}

/**
 * Exchanges a refresh token for its principal and revokes it (rotation).
 * Presenting an already-revoked token means it leaked: every session of that principal is revoked.
 */
export async function consumeRefreshToken(token: string): Promise<Principal | null> {
  const sql = db();
  const [row] = await sql<{ id: string; user_id: string | null; participant_id: string | null; revoked_at: Date | null; expires_at: Date }[]>`
    select id, user_id, participant_id, revoked_at, expires_at from refresh_tokens where token_hash = ${sha256(token)}`;
  if (!row) return null;
  if (row.revoked_at) {
    await sql`
      update refresh_tokens set revoked_at = now()
      where revoked_at is null
        and (user_id = ${row.user_id} or participant_id = ${row.participant_id})`;
    return null;
  }
  if (row.expires_at.getTime() <= Date.now()) return null;
  const revoked = await sql`update refresh_tokens set revoked_at = now() where id = ${row.id} and revoked_at is null`;
  if (revoked.count === 0) return null; // lost a race with a concurrent refresh
  return row.user_id ? { kind: "admin", userId: row.user_id } : { kind: "participant", participantId: row.participant_id! };
}

export async function revokeRefreshToken(token: string): Promise<void> {
  await db()`update refresh_tokens set revoked_at = now() where token_hash = ${sha256(token)} and revoked_at is null`;
}

// MARK: - Passwords (scrypt)

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const hash = await scryptAsync(password, salt, 64);
  return `scrypt$${salt.toString("base64")}$${hash.toString("base64")}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [scheme, saltB64, hashB64] = stored.split("$");
  if (scheme !== "scrypt" || !saltB64 || !hashB64) return false;
  const expected = Buffer.from(hashB64, "base64");
  const actual = await scryptAsync(password, Buffer.from(saltB64, "base64"), expected.length);
  return timingSafeEqual(actual, expected);
}

/** Compared against when the email is unknown, so response time doesn't reveal which emails exist. */
export const DUMMY_PASSWORD_HASH = "scrypt$AAAAAAAAAAAAAAAAAAAAAA==$" + Buffer.alloc(64).toString("base64");

// MARK: - Join codes

// No 0/O, 1/I/L: codes are read aloud and typed on phones.
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const CODE_LENGTH = 6;

export function generateJoinCode(): string {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return code;
}

/** Uppercases and drops spaces/dashes so "k7m-2qx" matches "K7M2QX". */
export const normalizeCode = (raw: string) => raw.toUpperCase().replace(/[\s-]/g, "");

/** A code not used by any event or organization. */
export async function uniqueJoinCode(): Promise<string> {
  const sql = db();
  for (;;) {
    const code = generateJoinCode();
    const [taken] = await sql`
      select 1 from events where agent_code = ${code} or cf_code = ${code}
      union all select 1 from organizations where admin_code = ${code}
      limit 1`;
    if (!taken) return code;
  }
}

// MARK: - Rate limiting

/** Records one failed attempt for `key` (e.g. "login:<email>", "join:<ip>"). */
export async function recordFailure(key: string): Promise<void> {
  await db()`insert into auth_failures (key) values (${key})`;
}

/** True once `key` has `limit` failures within the last `minutes`. Also prunes day-old rows. */
export async function isRateLimited(key: string, limit: number, minutes: number): Promise<boolean> {
  const sql = db();
  await sql`delete from auth_failures where created_at < now() - interval '1 day'`;
  const [r] = await sql<{ n: number }[]>`
    select count(*)::int as n from auth_failures
    where key = ${key} and created_at > now() - make_interval(mins => ${minutes})`;
  return (r?.n ?? 0) >= limit;
}
