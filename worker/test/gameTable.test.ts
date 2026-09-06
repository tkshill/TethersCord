import { describe, expect, it } from "vitest";
import { call, claim, readState, seedAuth } from "./helpers";

async function firstProposalId(table: string, token: string): Promise<string> {
  const state = await readState(table, token);
  const id = state.proposals[0]?.id;
  if (!id) throw new Error("no proposal queued");
  return id;
}

describe("GameTable state machine", () => {
  describe("the proposal queue", () => {
    it("queues a player's add-boon without touching the pool, then applies it on accept", async () => {
      const table = "gt-propose-accept";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: player } = await seedAuth();

      const proposed = await call(table, "/stones/add-boon", { token: player });
      expect(proposed.status).toBe(204);

      let state = await readState(table, fac);
      expect(state.proposals).toHaveLength(1);
      expect(state.proposals[0].kind).toBe("add-boon");
      expect(state.stonePool).toHaveLength(4); // untouched while pending

      const id = state.proposals[0].id;
      const accepted = await call(table, `/proposals/${id}/accept`, { token: fac });
      expect(accepted.status).toBe(204);

      state = await readState(table, fac);
      expect(state.proposals).toHaveLength(0);
      expect(state.stonePool).toHaveLength(5);
      expect(state.stonePool.filter((s) => s === "Boon")).toHaveLength(3);
    });

    it("drops a rejected proposal with no effect", async () => {
      const table = "gt-propose-reject";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: player } = await seedAuth();

      await call(table, "/stones/add-boon", { token: player });
      const id = await firstProposalId(table, fac);
      const rejected = await call(table, `/proposals/${id}/reject`, { token: fac });
      expect(rejected.status).toBe(204);

      const state = await readState(table, fac);
      expect(state.proposals).toHaveLength(0);
      expect(state.stonePool).toHaveLength(4);
    });

    it("applies a facilitator's own add-boon directly, no proposal", async () => {
      const table = "gt-fac-direct";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      const res = await call(table, "/stones/add-boon", { token: fac });
      expect(res.status).toBe(204);

      const state = await readState(table, fac);
      expect(state.proposals).toHaveLength(0);
      expect(state.stonePool).toHaveLength(5);
    });
  });

  it("serialises concurrent mutations through withLock", async () => {
    const table = "gt-lock";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    await Promise.all([
      call(table, "/stones/add-boon", { token: fac }),
      call(table, "/stones/add-boon", { token: fac }),
      call(table, "/stones/add-boon", { token: fac }),
    ]);

    const state = await readState(table, fac);
    // 4 base + 3 added; a lost update would leave fewer.
    expect(state.stonePool).toHaveLength(7);
  });

  describe("the session lifecycle", () => {
    it("clears the session's floating boons and used abilities when it ends", async () => {
      const table = "gt-session-end";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: player } = await seedAuth();

      await call(table, "/session/start", {
        token: fac,
        body: { goal: "Reach the archive" },
      });
      await claim(table, player, 0);

      // Mint a floating boon by accepting an Add a Detail ability.
      await call(table, "/abilities/use", {
        token: player,
        body: { kind: "add-detail" },
      });
      const detailId = await firstProposalId(table, fac);
      await call(table, `/proposals/${detailId}/accept`, {
        token: fac,
        body: { text: "the door was left ajar" },
      });

      let state = await readState(table, fac);
      expect(state.floatingBoons).toHaveLength(1);
      expect(state.usedAbilities).toHaveLength(1);

      const ended = await call(table, "/session/end", { token: fac });
      expect(ended.status).toBe(204);

      state = await readState(table, fac);
      expect(state.session).toBeNull();
      expect(state.floatingBoons).toHaveLength(0);
      expect(state.usedAbilities).toHaveLength(0);
      expect(state.sessionHistory).toHaveLength(1);
      // NOTE: unresolved `proposals` / `overcome` / `pendingRoll` /
      // `committedBoons` are NOT cleared on session end yet — roadmap §12
      // ("Ending a session clears every unresolved pending state") tracks that.
    });

    it("refuses an ability with no running session", async () => {
      const table = "gt-no-session";
      const { token: player } = await seedAuth();
      await claim(table, player, 0);

      const res = await call(table, "/abilities/use", {
        token: player,
        body: { kind: "gain-insight" },
      });
      expect(res.status).toBe(400);
    });

    it("allows a once-per-session ability only once", async () => {
      const table = "gt-once";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: player } = await seedAuth();

      await call(table, "/session/start", {
        token: fac,
        body: { goal: "Once only" },
      });
      await claim(table, player, 0);

      await call(table, "/abilities/use", {
        token: player,
        body: { kind: "gain-insight" },
      });
      const id = await firstProposalId(table, fac);
      await call(table, `/proposals/${id}/accept`, {
        token: fac,
        body: { text: "a hidden ledger" },
      });

      const again = await call(table, "/abilities/use", {
        token: player,
        body: { kind: "gain-insight" },
      });
      expect(again.status).toBe(409);
    });
  });

  it("pays out an accepted Suggest Compel to both characters", async () => {
    const table = "gt-suggest-compel";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: ada } = await seedAuth();
    const { token: bea } = await seedAuth();

    await call(table, "/session/start", { token: fac, body: { goal: "Compels" } });
    await claim(table, ada, 0);
    await claim(table, bea, 1);

    await call(table, "/abilities/use", {
      token: ada,
      body: { kind: "suggest-compel", targetSlot: 1 },
    });
    const id = await firstProposalId(table, fac);
    const accepted = await call(table, `/proposals/${id}/accept`, { token: fac });
    expect(accepted.status).toBe(204);

    const state = await readState(table, fac);
    const fateBySlot = Object.fromEntries(
      state.characters.map((c) => [c.slot, c.fate]),
    );
    expect(fateBySlot[0]).toBe(1); // suggester
    expect(fateBySlot[1]).toBe(2); // compelled character
  });
});
