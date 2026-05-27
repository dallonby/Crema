import type { MiddlewareHandler } from "hono";

/**
 * In-memory token-bucket rate limiter, keyed by client IP. No external
 * dependency, no Redis — fine for a single-instance deploy. If you scale
 * horizontally swap this for a Redis-backed limiter (this module's API is
 * deliberately tiny so the swap is a one-file change).
 *
 * Usage:
 *   const limit = makeRateLimiter({ capacity: 20, refillPerSec: 1 });
 *   app.use("/profiles", limit);
 *
 * A bucket holds up to `capacity` tokens; each request consumes 1.
 * Tokens refill at `refillPerSec` continuously. When a request finds
 * the bucket empty → 429 with a `Retry-After` header.
 *
 * Buckets are reaped after `idleTimeoutMs` of inactivity to keep the
 * Map bounded for long-running processes.
 */

interface Bucket {
  tokens: number;
  lastRefillMs: number;
}

interface Options {
  capacity: number;
  refillPerSec: number;
  /** Drop bucket records older than this. Defaults to 10 minutes. */
  idleTimeoutMs?: number;
}

export function makeRateLimiter(opts: Options): MiddlewareHandler {
  const buckets = new Map<string, Bucket>();
  const cap = opts.capacity;
  const refill = opts.refillPerSec;
  const idleMs = opts.idleTimeoutMs ?? 10 * 60_000;

  // Periodic reap. setInterval keeps the event loop alive — fine for a
  // long-running server; for short-lived environments call .unref().
  const reaper = setInterval(() => {
    const cutoff = Date.now() - idleMs;
    for (const [key, b] of buckets) {
      if (b.lastRefillMs < cutoff) buckets.delete(key);
    }
  }, 60_000);
  reaper.unref?.();

  return async (c, next) => {
    // Best-effort IP. Trust `x-forwarded-for` only if you set it from a
    // trusted reverse proxy — otherwise spoofable. Fall back to "anon"
    // (rate-limits all unidentifiable traffic together).
    const ip =
      c.req.header("x-forwarded-for")?.split(",")[0].trim() ??
      c.req.header("x-real-ip")?.trim() ??
      "anon";

    const now = Date.now();
    let b = buckets.get(ip);
    if (!b) { b = { tokens: cap, lastRefillMs: now }; buckets.set(ip, b); }
    // Refill since last touch.
    const elapsedSec = (now - b.lastRefillMs) / 1000;
    b.tokens = Math.min(cap, b.tokens + elapsedSec * refill);
    b.lastRefillMs = now;

    if (b.tokens < 1) {
      const waitSec = Math.ceil((1 - b.tokens) / refill);
      c.header("Retry-After", String(waitSec));
      c.header("X-RateLimit-Limit",     String(cap));
      c.header("X-RateLimit-Remaining", "0");
      return c.json({ error: "rate limit exceeded" }, 429);
    }
    b.tokens -= 1;
    c.header("X-RateLimit-Limit",     String(cap));
    c.header("X-RateLimit-Remaining", String(Math.floor(b.tokens)));
    await next();
  };
}
