# Crema backend

Community profile sharing for the Crema espresso app. Self-hostable: Hono on
Node.js with Postgres. Sign in with Apple for identity.

## Quick start (local)

```bash
cd backend
docker compose up --build         # API on :8080, Postgres on :5432
```

Schema is applied automatically by Postgres on first boot
(`db-init/*.sql` → `/docker-entrypoint-initdb.d/`). To re-apply after
a schema change locally: `docker compose down -v` (wipes the volume),
then `docker compose up`.

Health check: `curl http://localhost:8080/health` → `{"ok":true}`.

## Production deploy

1. Provision a Postgres (Neon / Supabase / RDS / your own).
2. Set environment:
   - `DATABASE_URL` — Postgres connection string
   - `JWT_SECRET` — 32+ char random string (used to sign session tokens)
   - `APPLE_CLIENT_ID` — the bundle id Apple issues identity tokens for
     (default `coffee.crema.app`)
   - `GOOGLE_CLIENT_IDS` — comma-separated list of Google OAuth client ids
     to accept (typically one for iOS, one for Android, one for web).
     If unset, `/auth/sign-in-with-google` returns 501.
   - `PUBLIC_BASE_URL` — the user-facing URL of your deployment (used in
     share-link generation, e.g. `https://api.crema.coffee`)
   - **For Universal / App Links (optional, recommended):**
     - `APPLE_APP_ID` — `<team-id>.<bundle-id>`, e.g. `YDGQZ6G5L9.coffee.crema.app`
     - `ANDROID_PACKAGE_NAME` — `coffee.crema.app`
     - `ANDROID_SHA256_FINGERPRINTS` — comma-separated SHA-256 fingerprints
       of your Android signing certs (release + debug)
   When set, `/.well-known/apple-app-site-association` and
   `/.well-known/assetlinks.json` are served so tapping a `<base>/p/<id>`
   link in any iOS or Android app opens Crema directly when installed.
3. Build the image (or use a Docker registry):
   ```bash
   docker build -t crema-backend .
   docker run -p 8080:8080 \
     -e DATABASE_URL=… -e JWT_SECRET=… -e APPLE_CLIENT_ID=… -e PUBLIC_BASE_URL=… \
     crema-backend
   ```
4. Run migrations once after the first deploy:
   ```bash
   docker run --rm -e DATABASE_URL=… crema-backend npm run db:migrate
   ```

## Endpoints

| Method | Path                            | Auth | Description                       |
|--------|---------------------------------|------|-----------------------------------|
| POST   | `/auth/sign-in-with-apple`      | —    | Trade Apple identity token for session |
| POST   | `/auth/sign-in-with-google`     | —    | Trade Google ID token for session (iOS/Android/web) |
| GET    | `/users/me`                     | ✓    | Current user                       |
| PATCH  | `/users/me`                     | ✓    | Update display name / avatar       |
| GET    | `/users/:id`                    | —    | Public user profile                |
| GET    | `/users/:id/stats`              | —    | Profile/follower/following counts  |
| POST   | `/users/:id/follow`             | ✓    | Follow user                        |
| DELETE | `/users/:id/follow`             | ✓    | Unfollow                           |
| GET    | `/users/:id/followers`          | —    | Followers list                     |
| GET    | `/users/:id/following`          | —    | Following list                     |
| POST   | `/profiles`                     | ✓    | Upload brew profile                |
| GET    | `/profiles`                     | —    | Browse (recent, ?author=, ?cursor=, ?limit=) |
| GET    | `/profiles/:id`                 | —    | Fetch one (bumps download count)   |
| DELETE | `/profiles/:id`                 | ✓    | Author can delete                  |
| POST   | `/profiles/:id/like`            | ✓    | Like                               |
| DELETE | `/profiles/:id/like`            | ✓    | Unlike                             |
| GET    | `/.well-known/apple-app-site-association` | — | iOS Universal Links discovery      |
| GET    | `/.well-known/assetlinks.json`  | —    | Android App Links discovery        |

Auth header: `Authorization: Bearer <sessionToken>`.

## Sign in with Apple — server side

Apple identity tokens are RS256 JWTs signed by keys at
`https://appleid.apple.com/auth/keys`. We:

1. Fetch + cache those keys (`jose`'s `createRemoteJWKSet`).
2. Verify the iOS client's `identityToken` against `issuer = appleid.apple.com`
   and `audience = $APPLE_CLIENT_ID` (your bundle id).
3. Treat the `sub` claim as the stable Apple user id (per-app).
4. Upsert a `users` row keyed off that `sub`. On first sign-in the iOS
   client passes `displayName`; on subsequent sign-ins Apple doesn't send it
   so we keep the stored one.
5. Issue our own session JWT (`HS256`, signed with `$JWT_SECRET`). 365-day
   expiry; client refreshes by re-signing-in if rejected.

## Schema

- `users` — Apple-identified accounts.
- `profiles` — uploaded BrewProfile JSON + metadata.
- `likes` — (user, profile) edge; `profiles.likesCount` is the denormalised count.
- `follows` — (follower, followee) edge.

Migrations are managed by `drizzle-kit`. Generate after schema edits with
`npm run db:generate`.
