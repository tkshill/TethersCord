// worker/src/maintenance.ts

import type { Env } from "./types";

/** Messages older than this are dropped by the hourly cron. */
const MESSAGE_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * Invoked from the hourly cron trigger. `messages` is otherwise append-only —
 * the Durable Object only ever loads a recent window of it (`MESSAGE_WINDOW`) —
 * so without this the table grows unbounded toward the account-wide SQLite cap.
 * Thirty days is well beyond the recent window a live table reads and the
 * "load earlier" fetch reaches for.
 */
export async function pruneOldMessages(env: Env): Promise<void> {
  await env.DB.prepare(`DELETE FROM messages WHERE created_at < ?`)
    .bind(Date.now() - MESSAGE_RETENTION_MS)
    .run();
}
