// Prospect API — deployed to Vercel as a zero-config Hono app (this file's default export).
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { logger } from "hono/logger";
import { type AppEnv, requireUser } from "./lib/context.js";
import { auth } from "./routes/auth.js";
import { me } from "./routes/me.js";
import { orgs } from "./routes/orgs.js";

const app = new Hono<AppEnv>();

app.use(logger());

app.get("/", (c) => c.json({ name: "prospect-api", ok: true }));

app.route("/auth", auth);

app.use("/me", requireUser);
app.use("/me/*", requireUser);
app.use("/orgs", requireUser);
app.use("/orgs/*", requireUser);
app.route("/me", me);
app.route("/orgs", orgs);

app.notFound((c) => c.json({ error: "not_found", message: "Route not found" }, 404));

app.onError((err, c) => {
  if (err instanceof HTTPException) return err.getResponse();
  // Postgres unique violation → a readable conflict instead of a 500.
  if ((err as { code?: string }).code === "23505") {
    return c.json({ error: "conflict", message: "This name is already taken" }, 409);
  }
  console.error(err);
  return c.json({ error: "internal", message: "Unexpected server error" }, 500);
});

export default app;
