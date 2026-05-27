import type { MiddlewareHandler } from "hono";
import { eq } from "drizzle-orm";
import { db, schema } from "../db/client.js";
import { verifySessionToken } from "../auth/jwt.js";

export interface AuthVars {
  user: schema.User;
}

/**
 * Authentication middleware. Pulls a `Bearer <jwt>` token from
 * Authorization, verifies it, loads the user row, and stashes it on the
 * context. Routes that read `c.get("user")` must list this as middleware.
 */
export const requireUser: MiddlewareHandler<{ Variables: AuthVars }> =
  async (c, next) => {
    const header = c.req.header("Authorization") ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    if (!token) return c.json({ error: "missing bearer token" }, 401);

    let session;
    try { session = await verifySessionToken(token); }
    catch { return c.json({ error: "invalid session" }, 401); }

    const user = await db.query.users.findFirst({
      where: eq(schema.users.id, session.userId),
    });
    if (!user) return c.json({ error: "user gone" }, 401);
    c.set("user", user);
    await next();
  };
