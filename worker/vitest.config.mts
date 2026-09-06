import { defineConfig } from "vitest/config";
import {
  cloudflareTest,
  readD1Migrations,
} from "@cloudflare/vitest-pool-workers";

const here = new URL(".", import.meta.url).pathname;
const migrationsDir = new URL("./migrations", import.meta.url).pathname;

// The wrangler.jsonc at the repo root also declares `assets` / `run_worker_first`,
// which the workers pool does not model, so the worker bindings are spelled out
// here instead of pointing at that file. Keep the DO binding, D1 binding, vars,
// and compatibility date in step with wrangler.jsonc.
export default defineConfig(async () => {
  const migrations = await readD1Migrations(migrationsDir);

  return {
    plugins: [
      cloudflareTest({
        main: "./src/index.ts",
        miniflare: {
          // wrangler.jsonc runs prod on 2026-09-01, but the workerd bundled
          // with @cloudflare/vitest-pool-workers only supports dates up to
          // 2026-08-22. Nothing these tests exercise (routing, D1, DO storage)
          // changed in that window; bump this when the pool catches up.
          compatibilityDate: "2026-08-22",
          durableObjects: {
            GAME_TABLE: { className: "GameTable", useSQLite: true },
          },
          d1Databases: ["DB"],
          bindings: {
            DISCORD_CLIENT_ID: "test-client-id",
            DISCORD_CLIENT_SECRET: "test-client-secret",
            BOOTSTRAP_FACILITATOR_ID: "",
            // Consumed by test/apply-migrations.ts.
            TEST_MIGRATIONS: migrations,
          },
        },
      }),
    ],
    test: {
      // Anchor to worker/ so `pnpm run test:worker` works from the repo root.
      root: here,
      include: ["test/**/*.test.ts"],
      setupFiles: ["./test/apply-migrations.ts"],
    },
  };
});
