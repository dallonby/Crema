-- App Store Guideline 1.2: UGC apps must support reporting + blocking.
-- Applied automatically by Postgres on first boot for fresh installs.
-- For existing installs, run manually:  psql $DATABASE_URL -f 02-moderation.sql

CREATE TABLE IF NOT EXISTS reports (
  reporter_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  profile_id   TEXT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  reason       TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (reporter_id, profile_id)
);
CREATE INDEX IF NOT EXISTS reports_profile_idx ON reports(profile_id);

CREATE TABLE IF NOT EXISTS blocks (
  blocker_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (blocker_id, blocked_id)
);
