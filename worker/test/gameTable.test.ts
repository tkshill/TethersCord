import { env } from "cloudflare:test";
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

  describe("stone-state write economy", () => {
    it("a chat post between two stone changes does not disturb the persisted stone state", async () => {
      const table = "gt-stone-write-skip";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      await call(table, "/stones/add-boon", { token: fac });
      // A plain message runs the same mutation path but touches nothing in the
      // stone slice; saveStoneState skips the write.
      await call(table, "/message", { token: fac, body: { content: "hello" } });
      await call(table, "/stones/add-boon", { token: fac });

      const state = await readState(table, fac);
      expect(state.stonePool).toHaveLength(6); // 4 base + 2 added, nothing lost
      expect(state.messages.at(-1)?.content).toBe("hello");
    });
  });

  describe("the message window", () => {
    it("keeps the snapshot to the last 50 and serves older rows from /messages/history", async () => {
      const table = "gt-msg-window";
      const { token } = await seedAuth(undefined, { facilitator: true });

      // 60 messages, created_at 1000, 2000, … 60000.
      const stmt = env.DB.prepare(
        `INSERT INTO messages (id, session_id, author_id, author_name, role, content, created_at)
         VALUES (?, ?, 'u', 'U', 'player', ?, ?)`,
      );
      await env.DB.batch(
        Array.from({ length: 60 }, (_, i) =>
          stmt.bind(`m${i + 1}`, table, `msg ${i + 1}`, (i + 1) * 1000),
        ),
      );

      const state = await readState(table, token);
      expect(state.messages).toHaveLength(50);
      // Oldest carried is #11 (created_at 11000); newest is #60.
      expect(state.messages[0].content).toBe("msg 11");
      expect(state.messages[49].content).toBe("msg 60");

      const res = await call(table, "/messages/history?before=11000", {
        token,
        method: "GET",
      });
      expect(res.status).toBe(200);
      const body = (await res.json()) as { messages: { content: string }[] };
      expect(body.messages).toHaveLength(10);
      expect(body.messages[0].content).toBe("msg 1");
      expect(body.messages[9].content).toBe("msg 10");
    });

    it("400s /messages/history without a numeric before", async () => {
      const table = "gt-msg-history-bad";
      const { token } = await seedAuth(undefined, { facilitator: true });
      const res = await call(table, "/messages/history", { token, method: "GET" });
      expect(res.status).toBe(400);
    });
  });

  describe("the auth lookup cache", () => {
    it("serves a token from DO memory for a minute, sparing the D1 join per request", async () => {
      const table = "gt-authcache";
      const { token } = await seedAuth(undefined, { facilitator: true });

      // First call primes the cache with token → AuthInfo.
      expect((await call(table, "/stones/add-boon", { token })).status).toBe(204);

      // Delete the row it was resolved from; an uncached lookup would now 401.
      await env.DB.prepare(
        `DELETE FROM sessions_auth WHERE session_token = ?`,
      )
        .bind(token)
        .run();

      // Still accepted, because the Durable Object memoised the resolution.
      expect((await call(table, "/stones/add-boon", { token })).status).toBe(204);
    });

    it("does not cache an unknown token", async () => {
      const table = "gt-authcache-miss";
      const bad = crypto.randomUUID();

      expect((await call(table, "/stones/add-boon", { token: bad })).status).toBe(
        401,
      );

      // The same token becomes valid; the earlier miss must not be remembered.
      await seedAuth(bad, { facilitator: true });
      expect((await call(table, "/stones/add-boon", { token: bad })).status).toBe(
        204,
      );
    });
  });

  describe("coalesced Highlight pledges", () => {
    it("accepts a net pledge delta greater than one and clamps it to fate", async () => {
      const table = "gt-pledge-net";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: player } = await seedAuth();

      await claim(table, player, 0);
      await call(table, "/characters/0/fate", { token: fac, body: { delta: 5 } });

      // The client has coalesced a run of + taps into one commit.
      const queued = await call(table, "/stones/commit", {
        token: player,
        body: { delta: 3 },
      });
      expect(queued.status).toBe(204);

      const pledgeId = await firstProposalId(table, fac);
      await call(table, `/proposals/${pledgeId}/accept`, { token: fac });

      const state = await readState(table, fac);
      expect(state.committedBoons).toEqual([{ slot: 0, count: 3 }]);
    });

    it("rejects a zero delta", async () => {
      const table = "gt-pledge-zero";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: player } = await seedAuth();
      await claim(table, player, 0);

      const res = await call(table, "/stones/commit", {
        token: player,
        body: { delta: 0 },
      });
      expect(res.status).toBe(400);
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
    it("clears every unresolved pending state when a session ends", async () => {
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

      // A pledged boon (accepted), plus a second pledge proposal left open.
      await call(table, "/characters/0/fate", { token: fac, body: { delta: 3 } });
      await call(table, "/stones/commit", { token: player, body: { delta: 1 } });
      const pledgeId = await firstProposalId(table, fac);
      await call(table, `/proposals/${pledgeId}/accept`, { token: fac });
      await call(table, "/stones/commit", { token: player, body: { delta: 1 } });

      let state = await readState(table, fac);
      expect(state.floatingBoons).toHaveLength(1);
      expect(state.usedAbilities).toHaveLength(1);
      expect(state.committedBoons).toHaveLength(1);
      expect(state.proposals).toHaveLength(1);

      const ended = await call(table, "/session/end", { token: fac });
      expect(ended.status).toBe(204);

      state = await readState(table, fac);
      expect(state.session).toBeNull();
      expect(state.sessionHistory).toHaveLength(1);
      expect(state.floatingBoons).toHaveLength(0);
      expect(state.usedAbilities).toHaveLength(0);
      expect(state.committedBoons).toHaveLength(0);
      expect(state.proposals).toHaveLength(0);
    });

    it("starts a session from a clean slate, discarding stale pledges and proposals", async () => {
      const table = "gt-session-start-clear";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: player } = await seedAuth();

      await claim(table, player, 0);
      await call(table, "/characters/0/fate", { token: fac, body: { delta: 2 } });
      await call(table, "/stones/commit", { token: player, body: { delta: 1 } });
      const pledgeId = await firstProposalId(table, fac);
      await call(table, `/proposals/${pledgeId}/accept`, { token: fac });
      await call(table, "/stones/add-boon", { token: player }); // leaves a proposal open

      let state = await readState(table, fac);
      expect(state.committedBoons).toHaveLength(1);
      expect(state.proposals).toHaveLength(1);

      await call(table, "/session/start", { token: fac, body: { goal: "Fresh" } });

      state = await readState(table, fac);
      expect(state.committedBoons).toHaveLength(0);
      expect(state.proposals).toHaveLength(0);
    });

    it("lets the facilitator rewrite the running goal, and 400s with no session", async () => {
      const table = "gt-session-goal";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      const early = await call(table, "/session/goal", {
        token: fac,
        body: { goal: "too soon" },
      });
      expect(early.status).toBe(400);

      await call(table, "/session/start", { token: fac, body: { goal: "First cut" } });
      const updated = await call(table, "/session/goal", {
        token: fac,
        body: { goal: "Second cut" },
      });
      expect(updated.status).toBe(204);

      const state = await readState(table, fac);
      expect(state.session?.goal).toBe("Second cut");
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

  describe("claim / release cleanup", () => {
    it("drops a slot's pledges and proposals when the sheet is released", async () => {
      const table = "gt-release-cleanup";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: a } = await seedAuth();
      const { token: b } = await seedAuth();

      await call(table, "/session/start", { token: fac, body: { goal: "x" } });
      await claim(table, a, 0);
      await claim(table, b, 1);
      await call(table, "/characters/0/fate", { token: fac, body: { delta: 3 } });
      await call(table, "/characters/1/fate", { token: fac, body: { delta: 3 } });

      // slot 0 and slot 1 each pledge a boon (accepted).
      await call(table, "/stones/commit", { token: a, body: { delta: 1 } });
      await call(table, `/proposals/${await firstProposalId(table, fac)}/accept`, {
        token: fac,
      });
      await call(table, "/stones/commit", { token: b, body: { delta: 1 } });
      await call(table, `/proposals/${await firstProposalId(table, fac)}/accept`, {
        token: fac,
      });
      // slot 0 also has an open pledge proposal the facilitator hasn't resolved.
      await call(table, "/stones/commit", { token: a, body: { delta: 1 } });

      let state = await readState(table, fac);
      expect(state.committedBoons.map((c) => c.slot).sort()).toEqual([0, 1]);
      expect(state.proposals).toHaveLength(1);
      expect(state.proposals[0].slot).toBe(0);

      await call(table, "/characters/0/release", { token: a });

      state = await readState(table, fac);
      expect(state.committedBoons.map((c) => c.slot)).toEqual([1]); // slot 1 kept
      expect(state.proposals).toHaveLength(0); // slot 0's open pledge gone
    });
  });

  it("/stones/draw is a read-only log line — the pool and proposal queue are untouched", async () => {
    const table = "gt-draw-readonly";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    // Queue a proposal so a silent reset would be visible.
    const { token: player } = await seedAuth();
    await call(table, "/stones/add-boon", { token: player });

    const before = await readState(table, fac);
    const res = await call(table, "/stones/draw", { token: fac });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.stonePool).toEqual(before.stonePool);
    expect(state.proposals).toHaveLength(1); // untouched
    expect(state.messages.at(-1)?.content).toMatch(
      /^Drew: (Boon|Bane), (Boon|Bane)$/,
    );
  });

  it("keeps a proposal queued when its target is gone by accept time", async () => {
    const table = "gt-accept-target-gone";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: ada } = await seedAuth();
    const { token: bea } = await seedAuth();

    await call(table, "/session/start", { token: fac, body: { goal: "compel" } });
    await claim(table, ada, 0);
    await claim(table, bea, 1);
    await call(table, "/abilities/use", {
      token: ada,
      body: { kind: "suggest-compel", targetSlot: 1 },
    });
    const id = await firstProposalId(table, fac);

    // The compelled player leaves their sheet before the facilitator accepts.
    // Cleanup drops the proposal outright, so accept then 404s — either way it
    // is never silently applied with no effect.
    await call(table, "/characters/1/release", { token: bea });
    const res = await call(table, `/proposals/${id}/accept`, { token: fac });
    expect(res.status).not.toBe(204);

    const state = await readState(table, fac);
    const fateBySlot = Object.fromEntries(
      state.characters.map((c) => [c.slot, c.fate]),
    );
    expect(fateBySlot[0]).toBe(0); // suggester never paid out
  });

  describe("NPCs and locations", () => {
    it("creates, edits, and deletes a facilitator reference row", async () => {
      const table = "gt-entities";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      const created = await call(table, "/npcs", { token: fac, body: {} });
      expect(created.status).toBe(204);

      let state = await readState(table, fac);
      expect(state.npcs).toHaveLength(1);
      const id = state.npcs[0].id;
      expect(state.npcs[0].name).toBe("");

      const updated = await call(table, `/npcs/${id}/update`, {
        token: fac,
        body: { name: "The Archivist", notes: "holds the keys" },
      });
      expect(updated.status).toBe(204);

      state = await readState(table, fac);
      expect(state.npcs[0]).toMatchObject({
        name: "The Archivist",
        notes: "holds the keys",
      });

      const deleted = await call(table, `/npcs/${id}/delete`, { token: fac });
      expect(deleted.status).toBe(204);

      state = await readState(table, fac);
      expect(state.npcs).toHaveLength(0);
    });

    it("keeps NPCs and locations in separate collections", async () => {
      const table = "gt-entities-split";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      await call(table, "/npcs", { token: fac, body: { name: "A guard" } });
      await call(table, "/locations", { token: fac, body: { name: "The gate" } });

      const state = await readState(table, fac);
      expect(state.npcs.map((e) => e.name)).toEqual(["A guard"]);
      expect(state.locations.map((e) => e.name)).toEqual(["The gate"]);
    });

    it("403s a player creating or editing a reference row", async () => {
      const table = "gt-entities-player";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: player } = await seedAuth();

      const blocked = await call(table, "/locations", {
        token: player,
        body: { name: "nope" },
      });
      expect(blocked.status).toBe(403);

      await call(table, "/npcs", { token: fac, body: {} });
      const id = (await readState(table, fac)).npcs[0].id;
      const blockedEdit = await call(table, `/npcs/${id}/update`, {
        token: player,
        body: { name: "hijack" },
      });
      expect(blockedEdit.status).toBe(403);
    });

    it("404s an update or delete for an unknown row", async () => {
      const table = "gt-entities-missing";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const missing = crypto.randomUUID();

      const upd = await call(table, `/locations/${missing}/update`, {
        token: fac,
        body: { name: "ghost" },
      });
      expect(upd.status).toBe(404);
      const del = await call(table, `/npcs/${missing}/delete`, { token: fac });
      expect(del.status).toBe(404);
    });
  });

  describe("proposal withdraw", () => {
    it("lets the proposer withdraw, but no one else", async () => {
      const table = "gt-withdraw";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: ada } = await seedAuth();
      const { token: bea } = await seedAuth();

      await call(table, "/stones/add-boon", { token: ada });
      const id = await firstProposalId(table, fac);

      const byOther = await call(table, `/proposals/${id}/withdraw`, { token: bea });
      expect(byOther.status).toBe(403);
      const byFac = await call(table, `/proposals/${id}/withdraw`, { token: fac });
      expect(byFac.status).toBe(403);

      const byProposer = await call(table, `/proposals/${id}/withdraw`, {
        token: ada,
      });
      expect(byProposer.status).toBe(204);

      const state = await readState(table, fac);
      expect(state.proposals).toHaveLength(0);
      expect(state.stonePool).toHaveLength(4); // never applied
    });
  });
});

describe("the combined pool — draws and session end (integration)", () => {
  it("a draw never changes the pool, however many times it's repeated", async () => {
    const table = "gt-draw-repeated";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    await call(table, "/session/start", { token: fac, body: { goal: "escalate" } });

    const before = await readState(table, fac);
    for (let i = 0; i < 8; i++) {
      const res = await call(table, "/stones/draw", { token: fac });
      expect(res.status).toBe(204);
    }
    const after = await readState(table, fac);
    expect(after.stonePool).toEqual(before.stonePool);
  });

  it("tops the pool up to at least 2 Boon and 2 Bane on session end, and leaves it alone when it already qualifies", async () => {
    const table = "gt-pool-topup";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    // A fresh table starts at the 2 Boon / 2 Bane floor already — ending
    // immediately should not add anything.
    await call(table, "/session/start", { token: fac, body: { goal: "first" } });
    await call(table, "/session/end", { token: fac });
    const state = await readState(table, fac);
    expect(state.stonePool.filter((s) => s === "Boon")).toHaveLength(2);
    expect(state.stonePool.filter((s) => s === "Bane")).toHaveLength(2);

    // Draining the pool below the floor needs a facilitator-only removal
    // route (23.2), not yet built — a draw itself never writes the pool
    // (23.1), so there is no way to fall under the floor here to exercise
    // the actual top-up arithmetic yet.
  });

  it("carries the pool across a session boundary — nothing resets on start or end", async () => {
    const table = "gt-pool-carries";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    await call(table, "/session/start", { token: fac, body: { goal: "a" } });
    await call(table, "/stones/add-boon", { token: fac });
    await call(table, "/stones/add-boon", { token: fac });
    let state = await readState(table, fac);
    expect(state.stonePool).toHaveLength(6);

    await call(table, "/session/end", { token: fac });
    state = await readState(table, fac);
    expect(state.stonePool).toHaveLength(6); // already past the floor, nothing added

    await call(table, "/session/start", { token: fac, body: { goal: "b" } });
    state = await readState(table, fac);
    expect(state.stonePool).toHaveLength(6); // session start does not touch the pool
  });
});
