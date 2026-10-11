import postgres from "postgres";

let client: postgres.Sql | undefined;

/** Shared connection pool, created on first use so imports never need DATABASE_URL. */
export function db(): postgres.Sql {
  if (!client) {
    const url = process.env.DATABASE_URL ?? process.env.POSTGRES_URL;
    if (!url) throw new Error("DATABASE_URL is not set");
    client = postgres(url, {
      max: Number(process.env.PG_POOL_MAX ?? 5),
      idle_timeout: 20,
      // Neon's pooler runs PgBouncer in transaction mode.
      prepare: false,
      // Keep DATE columns as "YYYY-MM-DD" strings instead of local-midnight Date objects.
      types: {
        date: {
          to: 1082,
          from: [1082],
          serialize: (x: string) => x,
          parse: (x: string) => x,
        },
      },
    });
  }
  return client;
}

export async function closeDb(): Promise<void> {
  await client?.end();
  client = undefined;
}
