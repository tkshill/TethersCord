import { describe, expect, it } from "vitest";
import { call, seedAuth } from "./helpers";

// The bearer-token gate on every /api/table route, and the facilitator-only
// gate on the privileged ones.
describe("route auth", () => {
  it("401s a request with no Authorization header", async () => {
    const res = await call("t-noauth", "/messages", { method: "GET" });
    expect(res.status).toBe(401);
  });

  it("401s an unknown bearer token", async () => {
    const res = await call("t-badtoken", "/messages", {
      method: "GET",
      token: "not-a-real-token",
    });
    expect(res.status).toBe(401);
  });

  it("401s an expired token", async () => {
    await seedAuth("expired", { expiresAt: Date.now() - 1000 });
    const res = await call("t-expired", "/messages", {
      method: "GET",
      token: "expired",
    });
    expect(res.status).toBe(401);
  });

  it("200s a valid token on a read", async () => {
    await seedAuth("valid-read");
    const res = await call("t-validread", "/messages", {
      method: "GET",
      token: "valid-read",
    });
    expect(res.status).toBe(200);
  });

  describe("facilitatorOnly", () => {
    it("403s a player calling /messages/clear", async () => {
      await seedAuth("player-clear");
      const res = await call("t-clear", "/messages/clear", {
        token: "player-clear",
      });
      expect(res.status).toBe(403);
    });

    it("403s a player calling /session/start", async () => {
      await seedAuth("player-sess");
      const res = await call("t-sess", "/session/start", {
        token: "player-sess",
        body: { goal: "nope" },
      });
      expect(res.status).toBe(403);
    });

    it("403s a player editing the session goal, 204s a facilitator", async () => {
      const table = "t-session-goal";
      await seedAuth("goal-fac", { facilitator: true });
      await seedAuth("goal-player");

      await call(table, "/session/start", {
        token: "goal-fac",
        body: { goal: "start" },
      });

      const byPlayer = await call(table, "/session/goal", {
        token: "goal-player",
        body: { goal: "hijack" },
      });
      expect(byPlayer.status).toBe(403);

      const byFac = await call(table, "/session/goal", {
        token: "goal-fac",
        body: { goal: "revised" },
      });
      expect(byFac.status).toBe(204);
    });

    it("lets a facilitator (via the facilitators table) clear the log", async () => {
      await seedAuth("fac-clear", { facilitator: true });
      const res = await call("t-facclear", "/messages/clear", {
        token: "fac-clear",
      });
      expect(res.status).toBe(204);
    });
  });

  describe("/overcome/roll", () => {
    it("204s a player rolling — Overcome is open to any player", async () => {
      await seedAuth("player-draw");
      const res = await call("t-draw", "/overcome/roll", { token: "player-draw" });
      expect(res.status).toBe(204);
    });

    it("401s an unauthenticated roll", async () => {
      const res = await call("t-nodraw", "/overcome/roll");
      expect(res.status).toBe(401);
    });

    it("204s a facilitator drawing", async () => {
      await seedAuth("fac-draw", { facilitator: true });
      const res = await call("t-facdraw", "/overcome/roll", { token: "fac-draw" });
      expect(res.status).toBe(204);
    });
  });
});
