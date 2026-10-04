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
      expect(state.die).toBe(10); // untouched while pending

      const id = state.proposals[0].id;
      expect(
        (await call(table, `/proposals/${id}/accept`, { token: fac })).status,
      ).toBe(204);

      state = await readState(table, fac);
      expect(state.proposals).toHaveLength(0);
      expect(state.die).toBe(12);
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

  describe("table-state write economy", () => {
    it("a chat post between two die steps does not disturb the persisted table state", async () => {
      const table = "gt-stone-write-skip";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      await call(table, "/die/step-up", { token: fac });
      // A plain message runs the same mutation path but touches nothing in the
      // table-state slice; saveTableState skips the write.
      await call(table, "/message", { token: fac, body: { content: "hello" } });
      await call(table, "/die/step-up", { token: fac });

      const state = await readState(table, fac);
      expect(state.die).toBe(16); // two steps, nothing lost
      expect(state.messages.map((m) => m.content)).toEqual([
        "Die stepped up — d10 → d12",
        "hello",
        "Die stepped up — d12 → d16",
      ]);
    });
  });

  describe("message kinds", () => {
    it("tags typed messages chat and mutation log lines event", async () => {
      const table = "gt-message-kinds";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      await call(table, "/message", { token: fac, body: { content: "hello" } });
      await call(table, "/junction/roll", { token: fac });

      const state = await readState(table, fac);
      expect(state.messages.map((m) => m.kind)).toEqual(["chat", "event"]);
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
      expect((await call(table, "/die/step-up", { token })).status).toBe(204);

      // Delete the row it was resolved from; an uncached lookup would now 401.
      await env.DB.prepare(
        `DELETE FROM sessions_auth WHERE session_token = ?`,
      )
        .bind(token)
        .run();

      // Still accepted, because the Durable Object memoised the resolution.
      expect((await call(table, "/die/step-up", { token })).status).toBe(204);
    });

    it("does not cache an unknown token", async () => {
      const table = "gt-authcache-miss";
      const bad = crypto.randomUUID();

      expect(
        (await call(table, "/die/step-up", { token: bad })).status,
      ).toBe(401);

      // The same token becomes valid; the earlier miss must not be remembered.
      await seedAuth(bad, { facilitator: true });
      expect(
        (await call(table, "/die/step-up", { token: bad })).status,
      ).toBe(204);
    });
  });

  it("serialises concurrent mutations through withLock", async () => {
    const table = "gt-lock";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    await Promise.all([
      call(table, "/die/step-up", { token: fac }),
      call(table, "/die/step-up", { token: fac }),
      call(table, "/die/step-up", { token: fac }),
    ]);

    const state = await readState(table, fac);
    // d10 up three rungs; a lost update would leave it lower.
    expect(state.die).toBe(20);
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

    it("keeps the in-memory history and the game_sessions row in step (one batch per mutation)", async () => {
      const table = "gt-session-history";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      await call(table, "/session/start", { token: fac, body: { goal: "First cut" } });
      await call(table, "/session/goal", { token: fac, body: { goal: "Second cut" } });
      await call(table, "/session/end", { token: fac });

      const state = await readState(table, fac);
      const row = await env.DB.prepare(
        `SELECT id, goal, started_at AS startedAt, ended_at AS endedAt
         FROM game_sessions WHERE session_id = ?`,
      )
        .bind(table)
        .first();
      expect(state.sessionHistory).toEqual([row]);
      expect(state.messages.map((m) => m.content)).toEqual([
        "Session started — First cut",
        "Goal updated — Second cut",
        "Session ended — Second cut",
      ]);
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

  describe("facilitator-run context aspects (23.2)", () => {
    it("creates and deletes a Boon session context directly, logging both", async () => {
      const table = "gt-facilitator-floating";
      const { token: fac, username: facName } = await seedAuth(undefined, {
        facilitator: true,
      });

      const created = await call(table, "/context-aspects", {
        token: fac,
        body: { kind: "Boon", text: "the vault door is ajar" },
      });
      expect(created.status).toBe(204);

      let state = await readState(table, fac);
      expect(state.contextAspects).toHaveLength(1);
      expect(state.contextAspects[0]).toMatchObject({
        kind: "Boon",
        text: "the vault door is ajar",
        createdByName: facName,
      });
      expect(state.messages.at(-1)?.content).toBe(
        "Session note added (Boon) — the vault door is ajar",
      );
      const id = state.contextAspects[0].id;

      const deleted = await call(table, `/context-aspects/${id}/delete`, {
        token: fac,
      });
      expect(deleted.status).toBe(204);

      state = await readState(table, fac);
      expect(state.contextAspects).toHaveLength(0);
      expect(state.messages.at(-1)?.content).toBe(
        "Session note removed (Boon) — the vault door is ajar",
      );
    });

    it("creates a Bane session context (23.3) the same way", async () => {
      const table = "gt-facilitator-floating-bane";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });

      const created = await call(table, "/context-aspects", {
        token: fac,
        body: { kind: "Bane", text: "the guard suspects something" },
      });
      expect(created.status).toBe(204);

      const state = await readState(table, fac);
      expect(state.contextAspects[0]).toMatchObject({
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

      const badKind = await call(table, "/context-aspects", {
        token: fac,
        body: { kind: "Coin", text: "nope" },
      });
      expect(badKind.status).toBe(400);

      const blank = await call(table, "/context-aspects", {
        token: fac,
        body: { kind: "Boon", text: "   " },
      });
      expect(blank.status).toBe(400);

      const missing = crypto.randomUUID();
      const del = await call(table, `/context-aspects/${missing}/delete`, {
        token: fac,
      });
      expect(del.status).toBe(404);
    });

    it("403s a player creating or deleting a session context", async () => {
      const table = "gt-facilitator-floating-player";
      const { token: fac } = await seedAuth(undefined, { facilitator: true });
      const { token: player } = await seedAuth();

      const create = await call(table, "/context-aspects", {
        token: player,
        body: { kind: "Boon", text: "nope" },
      });
      expect(create.status).toBe(403);

      const created = await call(table, "/context-aspects", {
        token: fac,
        body: { kind: "Boon", text: "a real one" },
      });
      expect(created.status).toBe(204);
      const id = (await readState(table, fac)).contextAspects[0].id;

      const del = await call(table, `/context-aspects/${id}/delete`, {
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
      expect(state.die).toBe(10); // never applied
    });
  });
});

describe("the die across sessions (integration)", () => {
  it("carries the die across a session boundary — nothing resets on start or end", async () => {
    const table = "gt-pool-carries";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    await call(table, "/session/start", { token: fac, body: { goal: "a" } });
    await call(table, "/die/step-up", { token: fac });
    await call(table, "/die/step-up", { token: fac });
    let state = await readState(table, fac);
    expect(state.die).toBe(16);

    await call(table, "/session/end", { token: fac });
    state = await readState(table, fac);
    expect(state.die).toBe(16);

    await call(table, "/session/start", { token: fac, body: { goal: "b" } });
    state = await readState(table, fac);
    expect(state.die).toBe(16);
  });
});
