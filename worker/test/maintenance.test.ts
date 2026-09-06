import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { pruneOldMessages } from "../src/maintenance";

const DAY = 24 * 60 * 60 * 1000;

async function seedMessage(id: string, createdAt: number): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO messages (id, session_id, author_id, author_name, role, content, created_at)
     VALUES (?, 't-prune', 'u', 'U', 'player', ?, ?)`,
  )
    .bind(id, id, createdAt)
    .run();
}

describe("pruneOldMessages", () => {
  it("deletes only messages older than the retention window", async () => {
    const now = Date.now();
    await seedMessage("fresh-1", now - 1 * DAY);
    await seedMessage("fresh-2", now - 29 * DAY);
    await seedMessage("stale-1", now - 31 * DAY);
    await seedMessage("stale-2", now - 400 * DAY);

    await pruneOldMessages(env);

    const { results } = await env.DB.prepare(
      `SELECT id FROM messages WHERE session_id = 't-prune' ORDER BY id`,
    ).all<{ id: string }>();
    expect(results.map((r) => r.id)).toEqual(["fresh-1", "fresh-2"]);
  });
});
