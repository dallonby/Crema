-- Initial schema for the Crema community backend.
-- Auto-applied by the Postgres docker image on first boot (anything in
-- /docker-entrypoint-initdb.d/ runs in alphabetical order against the
-- POSTGRES_DB database). For production deploys without docker, run this
-- file manually:  psql $DATABASE_URL -f 01-schema.sql.
--
-- Mirrors src/db/schema.ts. When you add columns there, add a new file
-- here (02-…sql) and apply it via your migration path of choice.

CREATE TABLE IF NOT EXISTS users (
  id              TEXT PRIMARY KEY,
  apple_user_id   TEXT UNIQUE,
  google_user_id  TEXT UNIQUE,
  display_name    TEXT NOT NULL,
  avatar_url      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS profiles (
  id                TEXT PRIMARY KEY,
  author_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name              TEXT NOT NULL,
  description       TEXT,
  bean_name         TEXT,
  equipment         TEXT,
  profile_json      JSONB NOT NULL,
  likes_count       INT NOT NULL DEFAULT 0,
  downloads_count   INT NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS profiles_author_idx  ON profiles(author_id);
CREATE INDEX IF NOT EXISTS profiles_created_idx ON profiles(created_at DESC);

CREATE TABLE IF NOT EXISTS likes (
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  profile_id  TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, profile_id)
);
CREATE INDEX IF NOT EXISTS likes_profile_idx ON likes(profile_id);

CREATE TABLE IF NOT EXISTS follows (
  follower_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  followee_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (follower_id, followee_id)
);
CREATE INDEX IF NOT EXISTS follows_followee_idx ON follows(followee_id);
