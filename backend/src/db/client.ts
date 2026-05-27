import pg from "pg";
import { drizzle } from "drizzle-orm/node-postgres";
import * as schema from "./schema.js";

const url = process.env.DATABASE_URL;
if (!url) throw new Error("DATABASE_URL not set");

const pool = new pg.Pool({
  connectionString: url,
  // Heroku-style postgres URLs need TLS; bare local urls don't.
  ssl: url.includes("sslmode=require") ? { rejectUnauthorized: false } : false,
});

export const db = drizzle(pool, { schema });
export { schema };
