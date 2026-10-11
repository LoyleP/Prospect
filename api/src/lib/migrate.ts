import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type postgres from "postgres";

const migrationsDir = fileURLToPath(new URL("../../db/migrations/", import.meta.url));

/** Applies every db/migrations/*.sql file not yet recorded, each in its own transaction. */
export async function migrate(sql: postgres.Sql, log: (msg: string) => void = () => {}): Promise<string[]> {
  await sql`create table if not exists schema_migrations (
    name text primary key,
    applied_at timestamptz not null default now()
  )`;

  const applied = new Set((await sql<{ name: string }[]>`select name from schema_migrations`).map((r) => r.name));
  const files = (await readdir(migrationsDir)).filter((f) => f.endsWith(".sql")).sort();
  const ran: string[] = [];

  for (const file of files) {
    if (applied.has(file)) continue;
    const body = await readFile(join(migrationsDir, file), "utf8");
    await sql.begin(async (tx) => {
      await tx.unsafe(body);
      await tx`insert into schema_migrations (name) values (${file})`;
    });
    log(`applied ${file}`);
    ran.push(file);
  }
  return ran;
}
