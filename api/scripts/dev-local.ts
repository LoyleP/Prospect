// Zero-setup local API: embedded Postgres (PGlite, persisted in api/.pglite) + the Hono server.
// Usage: npm run dev:local   → http://localhost:3000, login codes are printed in this terminal.
import { PGlite } from "@electric-sql/pglite";
import { PGLiteSocketServer } from "@electric-sql/pglite-socket";
import { serve } from "@hono/node-server";
import { fileURLToPath } from "node:url";

const DB_PORT = 54329;
const API_PORT = Number(process.env.PORT ?? 3000);

const pg = await PGlite.create(fileURLToPath(new URL("../.pglite", import.meta.url)));
const dbServer = new PGLiteSocketServer({ db: pg, port: DB_PORT, host: "127.0.0.1" });
await dbServer.start();

process.env.DATABASE_URL = `postgres://postgres:postgres@127.0.0.1:${DB_PORT}/postgres`;
process.env.PG_POOL_MAX = "1"; // PGlite serves one connection at a time
process.env.JWT_SECRET ??= "local-development-secret-not-for-production-use";

const { db } = await import("../src/lib/db.js");
const { migrate } = await import("../src/lib/migrate.js");
await migrate(db(), console.log);

const { default: app } = await import("../src/index.js");
serve({ fetch: app.fetch, port: API_PORT }, () => {
  console.log(`prospect-api (local, PGlite) on http://localhost:${API_PORT}`);
});
