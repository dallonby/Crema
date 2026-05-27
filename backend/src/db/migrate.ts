/**
 * Lightweight migration runner — pulls SQL from drizzle-kit's generated
 * migrations dir and runs them in order. Run via `npm run db:migrate`.
 * For prod, the Docker entrypoint can `npm run db:migrate && node dist/server.js`.
 */
import { migrate } from "drizzle-orm/node-postgres/migrator";
import { db } from "./client.js";

await migrate(db, { migrationsFolder: "./src/db/migrations" });
console.log("✔ migrations applied");
process.exit(0);
