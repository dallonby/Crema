# Crema Backend API

Hono on Node.js + Postgres. All requests/responses are JSON.

Base URL is whatever you've deployed at — `http://localhost:8080` for the
docker-compose dev setup. The iOS client reads it from
`UserDefaults["crema.backend.url.override"]`; Android will read it from
DataStore once that port lands.

## Auth

### POST `/auth/sign-in-with-apple`

```json
{
  "identityToken": "<JWT from ASAuthorizationAppleIDCredential.identityToken>",
  "displayName": "Dave"        // optional; only present on first sign-in per Apple
}
```

Response 200:
```json
{
  "sessionToken": "eyJhbGc…",   // HS256 JWT, store + send as Bearer
  "user": {
    "id": "k7Fp2nLmAB",
    "displayName": "Dave",
    "avatarUrl": null
  }
}
```

400 — body validation failed (Zod-formatted `error`).
401 — identity token failed Apple JWKS verification.

### POST `/auth/sign-in-with-google`

```json
{
  "identityToken": "<id_token from Google OAuth>",
  "displayName": "Dave"        // optional
}
```

Response shape identical to the Apple variant. `displayName` and
`avatarUrl` are populated from the Google ID token's `name` + `picture`
claims when present and the client didn't pass one.

501 — `GOOGLE_CLIENT_IDS` env var not set on the server.

## Session-authenticated requests

All endpoints below marked **auth** require `Authorization: Bearer <token>`.
401 if missing or expired.

## Users

### GET `/users/me`  (auth)

```json
{
  "user": {
    "id": "k7Fp2nLmAB",
    "displayName": "Dave",
    "avatarUrl": null,
    "createdAt": "2026-05-27T10:00:00.000Z"
  }
}
```

### PATCH `/users/me`  (auth)

Body — at least one of:
```json
{
  "displayName": "New Name",
  "avatarUrl": "https://…/avatar.png"
}
```

Response — full updated user, same shape as `GET /users/me`.

### GET `/users/:id`  (public)

Public user profile, same shape as `GET /users/me`'s `user`. 404 if not found.

### GET `/users/:id/stats`  (public)

```json
{
  "profiles":  12,    // shared profile count
  "followers": 8,
  "following": 15
}
```

### POST `/users/:id/follow`  (auth)  → `{ "ok": true }`
### DELETE `/users/:id/follow` (auth)  → `{ "ok": true }`

### GET `/users/:id/followers`  (public)
### GET `/users/:id/following`  (public)

```json
{ "users": [ { "id": …, "displayName": …, "avatarUrl": …, "createdAt": … }, … ] }
```

Up to 200 per page; pagination by `?cursor=` against `created_at` (newest first).

## Profiles

### POST `/profiles`  (auth)

```json
{
  "name": "Auto · Yirgacheffe",
  "description": "Bright + floral, my house bean",
  "beanName": "Cartwheel Yirgacheffe",
  "equipment": "Wendougee LITA-BA + Niche Zero",
  "profileJson": {
    "id": "uuid",
    "name": "Auto · Yirgacheffe",
    "stages": [ … BrewStage shape, see iOS BrewProfile.swift … ],
    "mode": "flowVariablePressure",
    "target": "flow",
    "targetVolumeMl": 36,
    "grinder": { "grindSizeMicrons": 76, "rpm": 567, "singleDose": true }
  }
}
```

Response 201:
```json
{
  "profile": {
    "id": "k7Fp2nLm",
    "name": "Auto · Yirgacheffe",
    "description": …, "beanName": …, "equipment": …,
    "profileJson": { … },
    "likesCount": 0,
    "downloadsCount": 0,
    "createdAt": "2026-05-27T10:30:00.000Z",
    "author": { "id": "k7Fp2nLmAB", "displayName": "Dave", "avatarUrl": null }
  },
  "url":      "https://api.crema.coffee/p/k7Fp2nLm",
  "deepLink": "crema://profile/k7Fp2nLm"
}
```

### GET `/profiles/:id`  (public)

```json
{ "profile": { … same shape as upload response's profile … } }
```

Also bumps `downloadsCount` server-side (best-effort, fire-and-forget).

### GET `/profiles`  (public)

Query params:
- `cursor` — ISO timestamp; returns profiles with `created_at < cursor`
- `author` — filter to one user id
- `limit` — max 100, default 30

Response:
```json
{
  "profiles": [ { … profile … }, … ],
  "nextCursor": "2026-05-27T09:00:00.000Z"   // null when end of feed
}
```

### DELETE `/profiles/:id`  (auth, author only)  → `{ "ok": true }`

404 if not yours / not found.

### POST   `/profiles/:id/like`   (auth) → `{ "likesCount": 3 }`
### DELETE `/profiles/:id/like`  (auth) → `{ "likesCount": 2 }`

Idempotent — repeated likes / unlikes don't double-count.

## Discovery

### GET `/health`  → `{ "ok": true }`
### GET `/`        → service + version + endpoint list

### GET `/.well-known/apple-app-site-association`

Apple Universal Links discovery. Served only when `APPLE_APP_ID` env is
set. Content-Type is `application/json` (no `.json` extension — Apple is
strict about this).

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["YDGQZ6G5L9.coffee.crema.app"],
        "components": [ { "/": "/p/*", "comment": "Shared profile permalinks" } ]
      }
    ]
  },
  "appclips": { "apps": ["YDGQZ6G5L9.coffee.crema.app"] }
}
```

### GET `/.well-known/assetlinks.json`

Android App Links discovery. Served only when both `ANDROID_PACKAGE_NAME`
and `ANDROID_SHA256_FINGERPRINTS` envs are set.

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "coffee.crema.app",
      "sha256_cert_fingerprints": ["AA:BB:CC:…"]
    }
  }
]
```

## Errors

All non-2xx responses are JSON: `{ "error": "<string>" }` or, for Zod
validation failures, `{ "error": <ZodFormattedError> }`.

| Status | When |
|--------|------|
| 400 | Body validation failed |
| 401 | Missing / invalid / expired session, or rejected identity token |
| 404 | Resource not found, or not owned by you (for delete) |
| 501 | Provider not configured (e.g. Google sign-in without `GOOGLE_CLIENT_IDS`) |

## BrewProfile JSON shape

Authoritative source: [`Sources/CremaKit/BrewProfile.swift`](../Sources/CremaKit/BrewProfile.swift). The
Android port must encode/decode this verbatim. Notable points:

- `mode` is an integer enum (`Int` raw value of `BrewMode`):
  `0=pressureFixedFlow`, `1=pressureVariableFlow`, `2=flowVariablePressure`,
  `3=flowFixedPressure`, `4=manual`. See `MachineConstants.swift`.
- `target` is `"flow" | "weight"` (string enum).
- `pressureBar` and `flowMlPerSec` are stored as `Double`. Stages set
  the appropriate one based on `priority`.
- `targetVolumeMl` is optional; auto-tune profiles bake in `200` as a
  safety ceiling (machine pump-volume cutoff, not cup yield).
- `grinder` is optional; when present writes via FF55 before brew start.
