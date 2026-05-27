import { Hono } from "hono";
import { z } from "zod";
import { and, desc, eq, lt, sql } from "drizzle-orm";
import { db, schema } from "../db/client.js";
import { newProfileId } from "../lib/id.js";
import { requireUser, type AuthVars } from "./middleware.js";

const profiles = new Hono<{ Variables: AuthVars }>();

// ---------------------------------------------------------------
// Validation
// ---------------------------------------------------------------

/** What the iOS client sends when uploading. The `profileJson` is the full
 *  BrewProfile blob — we don't reshape it here; the schema lives on the iOS
 *  side. We DO validate metadata fields we display ourselves. */
const UploadBody = z.object({
  name: z.string().min(1).max(80),
  description: z.string().max(2000).optional(),
  beanName: z.string().max(80).optional(),
  equipment: z.string().max(120).optional(),
  profileJson: z.record(z.unknown()),
});

// ---------------------------------------------------------------
// POST /profiles  — create
// ---------------------------------------------------------------
profiles.post("/", requireUser, async (c) => {
  const user = c.get("user");
  const body = UploadBody.safeParse(await c.req.json().catch(() => ({})));
  if (!body.success) return c.json({ error: body.error.format() }, 400);

  const id = newProfileId();
  const [row] = await db.insert(schema.profiles).values({
    id,
    authorId: user.id,
    name: body.data.name,
    description: body.data.description ?? null,
    beanName: body.data.beanName ?? null,
    equipment: body.data.equipment ?? null,
    profileJson: body.data.profileJson,
  }).returning();

  const base = process.env.PUBLIC_BASE_URL ?? "https://crema.local";
  return c.json({
    profile: shape(row, user),
    url: `${base}/p/${id}`,
    deepLink: `crema://profile/${id}`,
  }, 201);
});

// ---------------------------------------------------------------
// GET /profiles  — browse (recent, by author, cursor-paginated)
// ---------------------------------------------------------------
profiles.get("/", async (c) => {
  const authorId = c.req.query("author");
  const cursorIso = c.req.query("cursor");          // ISO timestamp
  const limit = Math.min(Number(c.req.query("limit")) || 30, 100);

  const where = [
    authorId ? eq(schema.profiles.authorId, authorId) : undefined,
    cursorIso ? lt(schema.profiles.createdAt, new Date(cursorIso)) : undefined,
  ].filter(Boolean);

  const rows = await db
    .select({ p: schema.profiles, u: schema.users })
    .from(schema.profiles)
    .innerJoin(schema.users, eq(schema.users.id, schema.profiles.authorId))
    .where(where.length ? and(...where) : undefined)
    .orderBy(desc(schema.profiles.createdAt))
    .limit(limit);

  return c.json({
    profiles: rows.map((r) => shape(r.p, r.u)),
    nextCursor: rows.length === limit
      ? rows[rows.length - 1].p.createdAt.toISOString()
      : null,
  });
});

// ---------------------------------------------------------------
// GET /profiles/:id  — fetch one (also bumps download count)
// ---------------------------------------------------------------
profiles.get("/:id", async (c) => {
  const id = c.req.param("id");
  const row = await db
    .select({ p: schema.profiles, u: schema.users })
    .from(schema.profiles)
    .innerJoin(schema.users, eq(schema.users.id, schema.profiles.authorId))
    .where(eq(schema.profiles.id, id))
    .limit(1);
  if (!row.length) return c.json({ error: "not found" }, 404);

  // Best-effort downloads-count bump — non-blocking; failure is harmless.
  db.update(schema.profiles)
    .set({ downloadsCount: sql`${schema.profiles.downloadsCount} + 1` })
    .where(eq(schema.profiles.id, id))
    .catch(() => {});

  return c.json({ profile: shape(row[0].p, row[0].u) });
});

// ---------------------------------------------------------------
// DELETE /profiles/:id  — author only
// ---------------------------------------------------------------
profiles.delete("/:id", requireUser, async (c) => {
  const user = c.get("user");
  const id = c.req.param("id");
  const result = await db
    .delete(schema.profiles)
    .where(and(eq(schema.profiles.id, id), eq(schema.profiles.authorId, user.id)))
    .returning({ id: schema.profiles.id });
  if (!result.length) return c.json({ error: "not found or not yours" }, 404);
  return c.json({ ok: true });
});

// ---------------------------------------------------------------
// Like toggle
// ---------------------------------------------------------------
profiles.post("/:id/like", requireUser, async (c) => {
  const user = c.get("user");
  const id = c.req.param("id");
  // ON CONFLICT DO NOTHING — idempotent
  await db.insert(schema.likes)
    .values({ userId: user.id, profileId: id })
    .onConflictDoNothing();
  const count = await bumpLikesCount(id);
  return c.json({ likesCount: count });
});

profiles.delete("/:id/like", requireUser, async (c) => {
  const user = c.get("user");
  const id = c.req.param("id");
  await db.delete(schema.likes).where(and(
    eq(schema.likes.userId, user.id),
    eq(schema.likes.profileId, id),
  ));
  const count = await bumpLikesCount(id);
  return c.json({ likesCount: count });
});

/** Recompute likes count from the truth table — small overhead, but keeps the
 *  denormalised column honest even when an idempotent insert is a no-op. */
async function bumpLikesCount(profileId: string): Promise<number> {
  const [{ count }] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(schema.likes)
    .where(eq(schema.likes.profileId, profileId));
  await db.update(schema.profiles)
    .set({ likesCount: count })
    .where(eq(schema.profiles.id, profileId));
  return count;
}

// ---------------------------------------------------------------
// Shape helper — never leak internal columns
// ---------------------------------------------------------------
function shape(p: schema.Profile, u: schema.User) {
  return {
    id: p.id,
    name: p.name,
    description: p.description,
    beanName: p.beanName,
    equipment: p.equipment,
    profileJson: p.profileJson,
    likesCount: p.likesCount,
    downloadsCount: p.downloadsCount,
    createdAt: p.createdAt.toISOString(),
    author: {
      id: u.id,
      displayName: u.displayName,
      avatarUrl: u.avatarUrl,
    },
  };
}

export default profiles;
