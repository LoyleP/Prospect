import { HTTPException } from "hono/http-exception";
import type { ContentfulStatusCode } from "hono/utils/http-status";
import type { z } from "zod";

/** Every API error is `{ "error": "<code>", "message": "<human text>" }`. */
export function apiError(status: ContentfulStatusCode, code: string, message: string): HTTPException {
  return new HTTPException(status, {
    res: new Response(JSON.stringify({ error: code, message }), {
      status,
      headers: { "Content-Type": "application/json" },
    }),
  });
}

export const notFound = (what = "Resource") => apiError(404, "not_found", `${what} not found`);
export const forbidden = () => apiError(403, "forbidden", "Your role does not allow this action");

/** Parses a JSON body against a schema, throwing a 400 that lists the first issue. */
export async function parseBody<T extends z.ZodType>(req: { json(): Promise<unknown> }, schema: T): Promise<z.infer<T>> {
  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    throw apiError(400, "invalid_json", "Request body must be JSON");
  }
  const result = schema.safeParse(raw);
  if (!result.success) {
    const issue = result.error.issues[0];
    const path = issue?.path.join(".") || "body";
    throw apiError(400, "invalid_request", `${path}: ${issue?.message ?? "invalid"}`);
  }
  return result.data;
}
