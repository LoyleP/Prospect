// Usage: npm run migrate   (reads DATABASE_URL from the environment or api/.env)
import { closeDb, db } from "../src/lib/db.js";
import { migrate } from "../src/lib/migrate.js";

const ran = await migrate(db(), console.log);
console.log(ran.length ? `${ran.length} migration(s) applied.` : "Database already up to date.");
await closeDb();
