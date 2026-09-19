import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { call, claim, readState, seedAuth } from "./helpers";

const ADD_BOON = { kind: "Boon" };

async function firstProposalId(table: string, token: string): Promise<string> {
  const state = await readState(table, token);
  const id = state.proposals[0]?.id;
  if (!id) throw new Error("no proposal queued");
  return id;
}

describe("GameTable state machine", () => {
  describe("the proposal queue", () => {
    it("queues a player's proposal without changing shared state, then applies it on accept", async () => {
      const table = "gt-propose-accept";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: player } = await seedAuth();
      await claim(table, player, 0);
      await call(table, "/characters/0/fate", { token: fac, body: { delta: 1 } });

      expect((await call(table, "/moves/highlight", { token: player })).status).toBe(
        204,
      );
      let state = await readState(table, fac);
      expect(state.proposals).toHaveLength(1);
      expect(state.stonePool).toHaveLength(4); // untouched while pending

      const id = state.proposals[0].id;
      expect(
        (await call(table, `/proposals/${id}/accept`, { token: fac })).status,
      ).toBe(204);

      state = await readState(table, fac);
      expect(state.proposals).toHaveLength(0);
      expect(state.stonePool).toHaveLength(5);
    });

    it("403s a player resolving a proposal", async () => {
      const table = "gt-propose-player-resolve";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: player } = await seedAuth();
      await claim(table, player, 0);
      await call(table, "/characters/0/fate", { token: fac, body: { delta: 1 } });
      await call(table, "/moves/highlight", { token: player });

      const id = await firstProposalId(table, fac);
      expect(
        (await call(table, `/proposals/${id}/accept`, { token: player })).status,
      ).toBe(403);
      expect(
        (await call(table, `/proposals/${id}/reject`, { token: player })).status,
      ).toBe(403);
    });
  });

  describe("stone-state write economy", () => {
    it("a chat post between two stone changes does not disturb the persisted stone state", async () => {
      const table = "gt-stone-write-skip";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      await call(table, "/stones/add", { token: fac, body: { kind: "Boon" } });
      // A plain message runs the same mutation path but touches nothing in the
      // stone slice; saveStoneState skips the write.
      await call(table, "/message", { token: fac, body: { content: "hello" } });
      await call(table, "/stones/add", { token: fac, body: { kind: "Boon" } });

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
      expect((await call(table, "/stones/add", { token, body: ADD_BOON })).status).toBe(204);

      // Delete the row it was resolved from; an uncached lookup would now 401.
      await env.DB.prepare(
        `DELETE FROM sessions_auth WHERE session_token = ?`,
      )
        .bind(token)
        .run();

      // Still accepted, because the Durable Object memoised the resolution.
      expect((await call(table, "/stones/add", { token, body: ADD_BOON })).status).toBe(204);
    });

    it("does not cache an unknown token", async () => {
      const table = "gt-authcache-miss";
      const bad = crypto.randomUUID();

      expect(
        (await call(table, "/stones/add", { token: bad, body: ADD_BOON })).status,
      ).toBe(401);

      // The same token becomes valid; the earlier miss must not be remembered.
      await seedAuth(bad, { facilitator: true });
      expect(
        (await call(table, "/stones/add", { token: bad, body: ADD_BOON })).status,
      ).toBe(204);
    });
  });

  it("serialises concurrent mutations through withLock", async () => {
    const table = "gt-lock";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    await Promise.all([
      call(table, "/stones/add", { token: fac, body: ADD_BOON }),
      call(table, "/stones/add", { token: fac, body: ADD_BOON }),
      call(table, "/stones/add", { token: fac, body: ADD_BOON }),
    ]);

    const state = await readState(table, fac);
    // 4 base + 3 added; a lost update would leave fewer.
    expect(state.stonePool).toHaveLength(7);
  });

  describe("the session lifecycle", () => {
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
  });

  describe("claim / release cleanup", () => {
    it("drops a slot's proposals when the sheet is released, and keeps everyone else's", async () => {
      const table = "gt-release-cleanup";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: a } = await seedAuth();
      const { token: b } = await seedAuth();

      await claim(table, a, 0);
      await claim(table, b, 1);
      await call(table, "/characters/0/fate", { token: fac, body: { delta: 3 } });
      await call(table, "/characters/1/fate", { token: fac, body: { delta: 3 } });

      // Each player has an open Highlight the facilitator hasn't resolved.
      await call(table, "/moves/highlight", { token: a });
      await call(table, "/moves/highlight", { token: b });

      let state = await readState(table, fac);
      expect(state.proposals.map((p) => p.slot).sort()).toEqual([0, 1]);

      await call(table, "/characters/0/release", { token: a });

      state = await readState(table, fac);
      expect(state.proposals.map((p) => p.slot)).toEqual([1]); // slot 0's gone
    });
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

  describe("facilitator-run resources (23.2)", () => {
    it("adds and removes a stone directly, no proposal", async () => {
      const table = "gt-facilitator-stones";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      const added = await call(table, "/stones/add", {
        token: fac,
        body: { kind: "Bane" },
      });
      expect(added.status).toBe(204);
      let state = await readState(table, fac);
      expect(state.stonePool.filter((s) => s === "Bane")).toHaveLength(3);
      expect(state.proposals).toHaveLength(0);

      const removed = await call(table, "/stones/remove", {
        token: fac,
        body: { kind: "Bane" },
      });
      expect(removed.status).toBe(204);
      state = await readState(table, fac);
      expect(state.stonePool.filter((s) => s === "Bane")).toHaveLength(2);
    });

    it("400s removing a kind the pool doesn't have, and 400s a bad kind either way", async () => {
      const table = "gt-facilitator-stones-bad";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      for (let i = 0; i < 4; i++) {
        await call(table, "/stones/remove", { token: fac, body: { kind: "Bane" } });
      }
      const drained = await readState(table, fac);
      expect(drained.stonePool.filter((s) => s === "Bane")).toHaveLength(0);

      const overDrawn = await call(table, "/stones/remove", {
        token: fac,
        body: { kind: "Bane" },
      });
      expect(overDrawn.status).toBe(400);

      const badAdd = await call(table, "/stones/add", {
        token: fac,
        body: { kind: "Coin" },
      });
      expect(badAdd.status).toBe(400);
      const badRemove = await call(table, "/stones/remove", {
        token: fac,
        body: { kind: "Coin" },
      });
      expect(badRemove.status).toBe(400);
    });

    it("403s a player adding or removing a stone", async () => {
      const table = "gt-facilitator-stones-player";
      const { token: player } = await seedAuth();

      const add = await call(table, "/stones/add", {
        token: player,
        body: { kind: "Boon" },
      });
      expect(add.status).toBe(403);
      const remove = await call(table, "/stones/remove", {
        token: player,
        body: { kind: "Boon" },
      });
      expect(remove.status).toBe(403);
    });

    it("creates and deletes a Boon session context directly, logging both", async () => {
      const table = "gt-facilitator-floating";
      const { token: fac, username: facName } = await seedAuth(undefined, {
        facilitator: true,
      });

      const created = await call(table, "/session-aspects", {
        token: fac,
        body: { kind: "Boon", text: "the vault door is ajar" },
      });
      expect(created.status).toBe(204);

      let state = await readState(table, fac);
      expect(state.sessionAspects).toHaveLength(1);
      expect(state.sessionAspects[0]).toMatchObject({
        kind: "Boon",
        text: "the vault door is ajar",
        createdByName: facName,
      });
      expect(state.messages.at(-1)?.content).toBe(
        "Session note added (Boon) — the vault door is ajar",
      );
      const id = state.sessionAspects[0].id;

      const deleted = await call(table, `/session-aspects/${id}/delete`, {
        token: fac,
      });
      expect(deleted.status).toBe(204);

      state = await readState(table, fac);
      expect(state.sessionAspects).toHaveLength(0);
      expect(state.messages.at(-1)?.content).toBe(
        "Session note removed (Boon) — the vault door is ajar",
      );
    });

    it("creates a Bane session context (23.3) the same way", async () => {
      const table = "gt-facilitator-floating-bane";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      const created = await call(table, "/session-aspects", {
        token: fac,
        body: { kind: "Bane", text: "the guard suspects something" },
      });
      expect(created.status).toBe(204);

      const state = await readState(table, fac);
      expect(state.sessionAspects[0]).toMatchObject({
        kind: "Bane",
        text: "the guard suspects something",
      });
      expect(state.messages.at(-1)?.content).toBe(
        "Session note added (Bane) — the guard suspects something",
      );
    });

    it("400s a missing/bad kind, an empty session context, 404s deleting an unknown one", async () => {
      const table = "gt-facilitator-floating-bad";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      const badKind = await call(table, "/session-aspects", {
        token: fac,
        body: { kind: "Coin", text: "nope" },
      });
      expect(badKind.status).toBe(400);

      const blank = await call(table, "/session-aspects", {
        token: fac,
        body: { kind: "Boon", text: "   " },
      });
      expect(blank.status).toBe(400);

      const missing = crypto.randomUUID();
      const del = await call(table, `/session-aspects/${missing}/delete`, {
        token: fac,
      });
      expect(del.status).toBe(404);
    });

    it("403s a player creating or deleting a session context", async () => {
      const table = "gt-facilitator-floating-player";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: player } = await seedAuth();

      const create = await call(table, "/session-aspects", {
        token: player,
        body: { kind: "Boon", text: "nope" },
      });
      expect(create.status).toBe(403);

      const created = await call(table, "/session-aspects", {
        token: fac,
        body: { kind: "Boon", text: "a real one" },
      });
      expect(created.status).toBe(204);
      const id = (await readState(table, fac)).sessionAspects[0].id;

      const del = await call(table, `/session-aspects/${id}/delete`, {
        token: player,
      });
      expect(del.status).toBe(403);
    });
  });

  describe("proposal withdraw", () => {
    it("lets the proposer withdraw, but no one else", async () => {
      const table = "gt-withdraw";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: ada } = await seedAuth();
      const { token: bea } = await seedAuth();
      await claim(table, ada, 0);
      await call(table, "/characters/0/fate", { token: fac, body: { delta: 1 } });

      await call(table, "/moves/highlight", { token: ada });
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

describe("the shared pool across sessions (integration)", () => {
  it("carries the pool across a session boundary — nothing resets on start or end", async () => {
    const table = "gt-pool-carries";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    await call(table, "/session/start", { token: fac, body: { goal: "a" } });
    await call(table, "/stones/add", { token: fac, body: ADD_BOON });
    await call(table, "/stones/add", { token: fac, body: ADD_BOON });
    let state = await readState(table, fac);
    expect(state.stonePool).toHaveLength(6);

    await call(table, "/session/end", { token: fac });
    state = await readState(table, fac);
    expect(state.stonePool).toHaveLength(6);

    await call(table, "/session/start", { token: fac, body: { goal: "b" } });
    state = await readState(table, fac);
    expect(state.stonePool).toHaveLength(6);
  });
});
