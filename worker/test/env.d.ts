import type { D1Migration } from "@cloudflare/vitest-pool-workers";
import type { Env as WorkerEnv } from "../src/types";

// `@cloudflare/vitest-pool-workers` types `env` from `cloudflare:test` as
// `Cloudflare.Env` but does not declare that namespace (it normally comes from
// `wrangler types`). Declare it here from the worker's own `Env`, plus the
// migrations binding the vitest config injects for test/apply-migrations.ts.
declare global {
  namespace Cloudflare {
    interface Env extends WorkerEnv {
      TEST_MIGRATIONS: D1Migration[];
    }
  }
}
