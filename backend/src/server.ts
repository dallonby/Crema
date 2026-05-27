import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import auth from "./routes/auth.js";
import profiles from "./routes/profiles.js";
import users from "./routes/users.js";

const app = new Hono();
app.use("*", logger());
app.use("*", cors({ origin: "*", allowMethods: ["GET", "POST", "PATCH", "DELETE"] }));

app.get("/", (c) => c.json({
  service: "crema-backend",
  version: "0.1.0",
  endpoints: ["/auth/sign-in-with-apple", "/me", "/profiles", "/users/:id"],
}));
app.get("/health", (c) => c.json({ ok: true }));

app.route("/auth", auth);
app.route("/profiles", profiles);
app.route("/users", users);

// `/me` is just a convenience alias for `/users/me` — let users hit either.
app.route("/me", new Hono().get("/", async (c) => {
  // delegate to /users/me with the same headers
  return c.redirect("/users/me", 307);
}));

const port = Number(process.env.PORT) || 8080;
serve({ fetch: app.fetch, port });
console.log(`crema-backend listening on :${port}`);
