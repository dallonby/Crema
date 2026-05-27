import { Hono } from "hono";
import { z } from "zod";
import { db, schema } from "../db/client.js";
import { eq } from "drizzle-orm";
import { verifyAppleIdentityToken } from "../auth/apple.js";
import { verifyGoogleIdToken } from "../auth/google.js";
import { issueSessionToken } from "../auth/jwt.js";
import { newUserId } from "../lib/id.js";

const SignInBody = z.object({
  identityToken: z.string().min(20),
  /** Apple/Google only return displayName on the very first sign-in.
   *  Clients should cache it and send it; we'll use it if a user record
   *  needs creating. */
  displayName: z.string().min(1).max(60).optional(),
});

const auth = new Hono();

const APPLE_AUDIENCE = process.env.APPLE_CLIENT_ID ?? "coffee.crema.app";
// Google: comma-separated list. iOS, Android, and web typically each have
// their own client id — accept any of them.
const GOOGLE_AUDIENCES = (process.env.GOOGLE_CLIENT_IDS ?? "")
  .split(",").map(s => s.trim()).filter(Boolean);

// ---------------------------------------------------------------
// Apple
// ---------------------------------------------------------------
auth.post("/sign-in-with-apple", async (c) => {
  const body = SignInBody.safeParse(await c.req.json().catch(() => ({})));
  if (!body.success) return c.json({ error: body.error.format() }, 400);

  let identity;
  try {
    identity = await verifyAppleIdentityToken(
      body.data.identityToken, APPLE_AUDIENCE);
  } catch {
    return c.json({ error: "invalid identity token" }, 401);
  }

  const user = await upsert({
    column: schema.users.appleUserId,
    providerId: identity.sub,
    displayName: body.data.displayName,
    avatarUrl: null,
  });
  const token = await issueSessionToken(user.id);
  return c.json({ sessionToken: token, user: shape(user) });
});

// ---------------------------------------------------------------
// Google (iOS, Android, web all post the same shape)
// ---------------------------------------------------------------
auth.post("/sign-in-with-google", async (c) => {
  if (GOOGLE_AUDIENCES.length === 0) {
    return c.json({ error: "google sign-in not configured (set GOOGLE_CLIENT_IDS)" }, 501);
  }
  const body = SignInBody.safeParse(await c.req.json().catch(() => ({})));
  if (!body.success) return c.json({ error: body.error.format() }, 400);

  let identity;
  try {
    identity = await verifyGoogleIdToken(body.data.identityToken, GOOGLE_AUDIENCES);
  } catch {
    return c.json({ error: "invalid identity token" }, 401);
  }

  // Google supplies name + picture inline — prefer those if the client
  // didn't pass a name.
  const user = await upsert({
    column: schema.users.googleUserId,
    providerId: identity.sub,
    displayName: body.data.displayName ?? identity.name,
    avatarUrl: identity.picture ?? null,
  });
  const token = await issueSessionToken(user.id);
  return c.json({ sessionToken: token, user: shape(user) });
});

// ---------------------------------------------------------------
// Shared user-upsert helper
// ---------------------------------------------------------------
async function upsert(args: {
  column: typeof schema.users.appleUserId | typeof schema.users.googleUserId;
  providerId: string;
  displayName?: string | null;
  avatarUrl?: string | null;
}) {
  const existing = await db.query.users.findFirst({
    where: eq(args.column, args.providerId),
  });
  if (existing) return existing;
  const id = newUserId();
  const name = args.displayName?.trim() || `User-${id.slice(0, 4)}`;
  const isApple = args.column === schema.users.appleUserId;
  const [user] = await db.insert(schema.users).values({
    id,
    appleUserId:  isApple ? args.providerId : null,
    googleUserId: isApple ? null            : args.providerId,
    displayName: name,
    avatarUrl: args.avatarUrl ?? null,
  }).returning();
  return user;
}

function shape(user: schema.User) {
  return {
    id: user.id,
    displayName: user.displayName,
    avatarUrl: user.avatarUrl,
  };
}

export default auth;
