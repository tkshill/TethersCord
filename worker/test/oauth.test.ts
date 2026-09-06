import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { handleDiscordExchange, pruneExpiredSessions } from "../src/oauth-discord";
import { seedAuth } from "./helpers";

describe("oauth-discord", () => {
  describe("pruneExpiredSessions", () => {
    it("deletes only the rows past their expiry", async () => {
      await seedAuth("live-1", { expiresAt: Date.now() + 60_000 });
      await seedAuth("live-2", { expiresAt: Date.now() + 60_000 });
      await seedAuth("dead-1", { expiresAt: Date.now() - 1 });
      await seedAuth("dead-2", { expiresAt: Date.now() - 60_000 });

      await pruneExpiredSessions(env);

      const { results } = await env.DB.prepare(
        `SELECT session_token FROM sessions_auth ORDER BY session_token`,
      ).all<{ session_token: string }>();
      expect(results.map((r) => r.session_token)).toEqual(["live-1", "live-2"]);
    });
  });

  describe("handleDiscordExchange input validation", () => {
    it("400s a non-JSON body", async () => {
      const res = await handleDiscordExchange(
        new Request("https://tetherscord.test/api/oauth/discord/exchange", {
          method: "POST",
          body: "not json",
        }),
        env,
      );
      expect(res.status).toBe(400);
    });

    it("400s a body with no code", async () => {
      const res = await handleDiscordExchange(
        new Request("https://tetherscord.test/api/oauth/discord/exchange", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({}),
        }),
        env,
      );
      expect(res.status).toBe(400);
      expect(await res.text()).toBe("Missing authorization code");
    });
  });
});
