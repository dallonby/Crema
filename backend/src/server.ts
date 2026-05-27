import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import auth from "./routes/auth.js";
import profiles from "./routes/profiles.js";
import users from "./routes/users.js";
import wellKnown from "./routes/wellKnown.js";

const app = new Hono();
app.use("*", logger());
app.use("*", cors({ origin: "*", allowMethods: ["GET", "POST", "PATCH", "DELETE"] }));

app.get("/", (c) => c.json({
  service: "crema-backend",
  version: "0.2.0",
  endpoints: [
    "/health",
    "/auth/sign-in-with-apple",
    "/auth/sign-in-with-google",
    "/users/me", "/users/:id", "/users/:id/follow",
    "/users/:id/followers", "/users/:id/following", "/users/:id/stats",
    "/profiles", "/profiles/:id", "/profiles/:id/like",
    "/.well-known/apple-app-site-association",
    "/.well-known/assetlinks.json",
  ],
}));
app.get("/health", (c) => c.json({ ok: true }));

app.route("/auth", auth);
app.route("/profiles", profiles);
app.route("/users", users);
app.route("/.well-known", wellKnown);

// `/me` is just a convenience alias for `/users/me` — let users hit either.
app.route("/me", new Hono().get("/", async (c) => {
  // delegate to /users/me with the same headers
  return c.redirect("/users/me", 307);
}));

const port = Number(process.env.PORT) || 8080;
serve({ fetch: app.fetch, port });
console.log(`crema-backend listening on :${port}`);
