import { describe, expect, it } from "vitest";
import { call, claim, seedAuth } from "./helpers";

// The bearer-token gate on every /api/table route, the facilitator-only gate on
// the privileged ones, and the roll gate that also lets the overcome target in.
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

    it("lets a facilitator (via the facilitators table) clear the log", async () => {
      await seedAuth("fac-clear", { facilitator: true });
      const res = await call("t-facclear", "/messages/clear", {
        token: "fac-clear",
      });
      expect(res.status).toBe(204);
    });
  });

  describe("rollGate", () => {
    it("403s a player rolling with no overcome open", async () => {
      await seedAuth("player-roll");
      const res = await call("t-roll", "/stones/roll", { token: "player-roll" });
      expect(res.status).toBe(403);
    });

    it("lets the facilitator roll", async () => {
      await seedAuth("fac-roll", { facilitator: true });
      const res = await call("t-facroll", "/stones/roll", { token: "fac-roll" });
      expect(res.status).toBe(204);
    });

    it("lets the overcome target roll, but not another player", async () => {
      const table = "t-overcome-roll";
      await seedAuth("fac-oc", { facilitator: true });
      await seedAuth("target", { userId: "target-user" });
      await seedAuth("bystander", { userId: "bystander-user" });

      await claim(table, "target", 0);
      const started = await call(table, "/overcome/start", {
        token: "fac-oc",
        body: { slot: 0 },
      });
      expect(started.status).toBe(204);

      const bystander = await call(table, "/stones/roll", {
        token: "bystander",
      });
      expect(bystander.status).toBe(403);

      const target = await call(table, "/stones/roll", { token: "target" });
      expect(target.status).toBe(204);
    });
  });
});
