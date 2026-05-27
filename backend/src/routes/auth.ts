import { Hono } from "hono";
import { z } from "zod";
import { db, schema } from "../db/client.js";
import { eq } from "drizzle-orm";
import { verifyAppleIdentityToken } from "../auth/apple.js";
import { issueSessionToken } from "../auth/jwt.js";
import { newUserId } from "../lib/id.js";

const SignInBody = z.object({
  identityToken: z.string().min(20),
  /** Apple only returns displayName on the very first sign-in. Clients should
   *  cache it and send it; we'll use it if a user record needs creating. */
  displayName: z.string().min(1).max(60).optional(),
});

const auth = new Hono();

const APPLE_AUDIENCE = process.env.APPLE_CLIENT_ID ?? "coffee.crema.app";

auth.post("/sign-in-with-apple", async (c) => {
  const body = SignInBody.safeParse(await c.req.json().catch(() => ({})));
  if (!body.success) return c.json({ error: body.error.format() }, 400);

  let identity;
  try {
    identity = await verifyAppleIdentityToken(
      body.data.identityToken, APPLE_AUDIENCE);
  } catch (e) {
    return c.json({ error: "invalid identity token" }, 401);
  }

  // Upsert user — keyed by Apple `sub`. Display name only set on insert
  // (Apple won't give it on subsequent sign-ins).
  const existing = await db.query.users.findFirst({
    where: eq(schema.users.appleUserId, identity.sub),
  });
  let user = existing;
  if (!user) {
    const id = newUserId();
    const name = body.data.displayName?.trim() || `User-${id.slice(0, 4)}`;
    [user] = await db.insert(schema.users).values({
      id, appleUserId: identity.sub, displayName: name,
    }).returning();
  }

  const token = await issueSessionToken(user.id);
  return c.json({
    sessionToken: token,
    user: {
      id: user.id,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
    },
  });
});

export default auth;
