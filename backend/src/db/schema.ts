import {
  pgTable, text, integer, timestamp, jsonb,
  primaryKey, index
} from "drizzle-orm/pg-core";

/**
 * Users — one row per identity. Either `appleUserId` or `googleUserId` (or
 * both, eventually) is set; the lookup path is by-provider. Both columns are
 * unique-when-non-null so we don't accidentally fork an account by signing
 * in via the other provider.
 *
 * A v2 will likely move to a separate `identities` table to support
 * properly merging accounts that signed in via different providers but
 * own the same email. For now, single-provider-per-user is simpler.
 */
export const users = pgTable("users", {
  id: text("id").primaryKey(),                     // nanoid
  appleUserId: text("apple_user_id").unique(),     // nullable — see above
  googleUserId: text("google_user_id").unique(),
  displayName: text("display_name").notNull(),
  avatarUrl: text("avatar_url"),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull().defaultNow(),
});

/**
 * Shared brew profiles. `profileJson` is the full `BrewProfile` blob the iOS
 * client uploads. `likesCount` / `downloadsCount` are denormalised
 * aggregates — updated transactionally when a like / download happens.
 */
export const profiles = pgTable("profiles", {
  id: text("id").primaryKey(),                     // short nanoid (8 chars)
  authorId: text("author_id").notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  description: text("description"),
  beanName: text("bean_name"),
  equipment: text("equipment"),
  profileJson: jsonb("profile_json").notNull(),
  likesCount: integer("likes_count").notNull().default(0),
  downloadsCount: integer("downloads_count").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull().defaultNow(),
}, (t) => ({
  authorIdx: index("profiles_author_idx").on(t.authorId),
  createdIdx: index("profiles_created_idx").on(t.createdAt),
}));

/**
 * Like edge — composite PK (user, profile). Soft natural dedup; toggling a
 * like is just upsert / delete. Counts are kept on `profiles.likesCount`.
 */
export const likes = pgTable("likes", {
  userId: text("user_id").notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  profileId: text("profile_id").notNull()
    .references(() => profiles.id, { onDelete: "cascade" }),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull().defaultNow(),
}, (t) => ({
  pk: primaryKey({ columns: [t.userId, t.profileId] }),
  profileIdx: index("likes_profile_idx").on(t.profileId),
}));

/**
 * Follow edge — user → user. Same shape as likes.
 */
export const follows = pgTable("follows", {
  followerId: text("follower_id").notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  followeeId: text("followee_id").notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull().defaultNow(),
}, (t) => ({
  pk: primaryKey({ columns: [t.followerId, t.followeeId] }),
  followeeIdx: index("follows_followee_idx").on(t.followeeId),
}));

export type User = typeof users.$inferSelect;
export type Profile = typeof profiles.$inferSelect;
