import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import auth from "./routes/auth.js";
import profiles from "./routes/profiles.js";
import users from "./routes/users.js";
import wellKnown from "./routes/wellKnown.js";
import preview from "./routes/preview.js";
import pages from "./routes/pages.js";
import { makeRateLimiter } from "./lib/rateLimit.js";

const app = new Hono();
app.use("*", logger());

// CORS — env-driven allowlist. Default to wildcard for dev convenience;
// for production set `CORS_ORIGINS="https://crema.coffee,https://app.crema.coffee"`
// to lock down which web origins can hit the API.
const corsOrigins = (process.env.CORS_ORIGINS ?? "*")
  .split(",").map(s => s.trim()).filter(Boolean);
app.use("*", cors({
  origin: corsOrigins.length === 1 && corsOrigins[0] === "*"
    ? "*"
    : (origin) => corsOrigins.includes(origin) ? origin : "",
  allowMethods: ["GET", "POST", "PATCH", "DELETE"],
}));

// Rate limiting. Auth is tightest (anti-brute-force on token-exchange);
// the rest get a generous bucket per IP. Single-instance in-memory state
// — see lib/rateLimit.ts for the swap-out path to Redis if you scale out.
const authLimit    = makeRateLimiter({ capacity: 10,  refillPerSec: 0.1 });
const generalLimit = makeRateLimiter({ capacity: 120, refillPerSec: 2.0 });

// Discovery JSON moved to /api so the apex can serve the marketing landing.
app.get("/api", (c) => c.json({
  service: "crema-backend",
  version: "0.2.0",
  endpoints: [
    "/health",
    "/auth/sign-in-with-apple",
    "/auth/sign-in-with-google",
    "/users/me", "/users/:id", "/users/:id/follow",
    "/users/:id/followers", "/users/:id/following", "/users/:id/stats",
    "/profiles", "/profiles/:id", "/profiles/:id/like",
    "/p/:id  (HTML preview)",
    "/privacy", "/support",
    "/.well-known/apple-app-site-association",
    "/.well-known/assetlinks.json",
  ],
}));
app.get("/health", (c) => c.json({ ok: true }));

app.use("/auth/*",     authLimit);
app.use("/profiles/*", generalLimit);
app.use("/profiles",   generalLimit);   // matches the collection root
app.use("/users/*",    generalLimit);
app.use("/p/*",        generalLimit);   // public profile preview hits DB
// `/health`, `/`, `/.well-known/*` deliberately unlimited.

app.route("/auth", auth);
app.route("/profiles", profiles);
app.route("/users", users);
app.route("/.well-known", wellKnown);
app.route("/p", preview);   // public HTML preview at /p/<id>
app.route("/", pages);      // /, /privacy, /support landing pages

// `/me` is just a convenience alias for `/users/me` — let users hit either.
app.route("/me", new Hono().get("/", async (c) => {
  // delegate to /users/me with the same headers
  return c.redirect("/users/me", 307);
}));

const port = Number(process.env.PORT) || 8080;
serve({ fetch: app.fetch, port });
console.log(`crema-backend listening on :${port}`);
