import { applyD1Migrations, env } from "cloudflare:test";

// Runs once per test file, before any test. Brings the isolated D1 instance up
// to the current schema from worker/migrations/.
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
