import { Hono } from "hono";
import { z } from "zod";
import { and, desc, eq, sql } from "drizzle-orm";
import { db, schema } from "../db/client.js";
import { requireUser, type AuthVars } from "./middleware.js";

const users = new Hono<{ Variables: AuthVars }>();

const UpdateMeBody = z.object({
  displayName: z.string().min(1).max(60).optional(),
  avatarUrl: z.string().url().nullable().optional(),
});

users.get("/me", requireUser, (c) => {
  const u = c.get("user");
  return c.json({ user: shapeUser(u) });
});

users.patch("/me", requireUser, async (c) => {
  const u = c.get("user");
  const body = UpdateMeBody.safeParse(await c.req.json().catch(() => ({})));
  if (!body.success) return c.json({ error: body.error.format() }, 400);
  const [updated] = await db.update(schema.users)
    .set(body.data)
    .where(eq(schema.users.id, u.id))
    .returning();
  return c.json({ user: shapeUser(updated) });
});

users.get("/:id", async (c) => {
  const id = c.req.param("id");
  const u = await db.query.users.findFirst({
    where: eq(schema.users.id, id),
  });
  if (!u) return c.json({ error: "not found" }, 404);
  return c.json({ user: shapeUser(u) });
});

// ---- Follow edges --------------------------------------------------------

users.post("/:id/follow", requireUser, async (c) => {
  const me = c.get("user");
  const targetId = c.req.param("id");
  if (targetId === me.id) return c.json({ error: "can't follow self" }, 400);
  await db.insert(schema.follows)
    .values({ followerId: me.id, followeeId: targetId })
    .onConflictDoNothing();
  return c.json({ ok: true });
});

users.delete("/:id/follow", requireUser, async (c) => {
  const me = c.get("user");
  const targetId = c.req.param("id");
  await db.delete(schema.follows).where(and(
    eq(schema.follows.followerId, me.id),
    eq(schema.follows.followeeId, targetId),
  ));
  return c.json({ ok: true });
});

users.get("/:id/followers", async (c) => {
  const id = c.req.param("id");
  const rows = await db
    .select({ u: schema.users })
    .from(schema.follows)
    .innerJoin(schema.users, eq(schema.users.id, schema.follows.followerId))
    .where(eq(schema.follows.followeeId, id))
    .orderBy(desc(schema.follows.createdAt))
    .limit(200);
  return c.json({ users: rows.map((r) => shapeUser(r.u)) });
});

users.get("/:id/following", async (c) => {
  const id = c.req.param("id");
  const rows = await db
    .select({ u: schema.users })
    .from(schema.follows)
    .innerJoin(schema.users, eq(schema.users.id, schema.follows.followeeId))
    .where(eq(schema.follows.followerId, id))
    .orderBy(desc(schema.follows.createdAt))
    .limit(200);
  return c.json({ users: rows.map((r) => shapeUser(r.u)) });
});

// ---- Block / unblock ----------------------------------------------------
// App Store Guideline 1.2 requires "the ability to block abusive users."
// Blocked authors are filtered out of GET /profiles when the caller is the
// blocker (see profiles route). Idempotent.

users.post("/:id/block", requireUser, async (c) => {
  const me = c.get("user");
  const targetId = c.req.param("id");
  if (targetId === me.id) return c.json({ error: "can't block self" }, 400);
  await db.insert(schema.blocks)
    .values({ blockerId: me.id, blockedId: targetId })
    .onConflictDoNothing();
  return c.json({ ok: true });
});

users.delete("/:id/block", requireUser, async (c) => {
  const me = c.get("user");
  const targetId = c.req.param("id");
  await db.delete(schema.blocks).where(and(
    eq(schema.blocks.blockerId, me.id),
    eq(schema.blocks.blockedId, targetId),
  ));
  return c.json({ ok: true });
});

users.get("/me/blocks", requireUser, async (c) => {
  const me = c.get("user");
  const rows = await db.select({ id: schema.blocks.blockedId,
                                  createdAt: schema.blocks.createdAt })
    .from(schema.blocks).where(eq(schema.blocks.blockerId, me.id));
  return c.json({ blocked: rows });
});

users.get("/:id/stats", async (c) => {
  const id = c.req.param("id");
  const [stats] = await db.select({
    profiles: sql<number>`(
      SELECT count(*)::int FROM ${schema.profiles}
      WHERE ${schema.profiles.authorId} = ${id})`,
    followers: sql<number>`(
      SELECT count(*)::int FROM ${schema.follows}
      WHERE ${schema.follows.followeeId} = ${id})`,
    following: sql<number>`(
      SELECT count(*)::int FROM ${schema.follows}
      WHERE ${schema.follows.followerId} = ${id})`,
  }).from(schema.users).where(eq(schema.users.id, id)).limit(1);
  return c.json(stats ?? { profiles: 0, followers: 0, following: 0 });
});

function shapeUser(u: schema.User) {
  return {
    id: u.id,
    displayName: u.displayName,
    avatarUrl: u.avatarUrl,
    createdAt: u.createdAt.toISOString(),
  };
}

export default users;
