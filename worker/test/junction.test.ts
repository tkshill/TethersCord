import { env, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import type { GameTable } from "../src/GameTable";
import { call, claim, readState, seedAuth } from "./helpers";

// The Junction loop through the routes (31.2b): roll the die, reroll, accept
// or reject, and the facilitator's direct die steps and context aspect use.
// These are wiring tests — status codes, the broadcast state, the log and what
// is stored. The rules themselves (every outcome, every refusal) are tested
// against `transition` in test/rules/junction.test.ts; a test here that needs
// a known face scripts the table's dice with `scriptRolls`.

/** Make the table's next rolls show `faces`, in order. */
async function scriptRolls(table: string, faces: number[]): Promise<void> {
  const stub = env.GAME_TABLE.get(env.GAME_TABLE.idFromName(table));
  await runInDurableObject(stub, (instance: GameTable) => {
    const deps = (instance as unknown as { deps: { roll: (sides: number) => number } }).deps;
    const queue = [...faces];
    (instance as unknown as { deps: object }).deps = {
      ...deps,
      roll: () => {
        const face = queue.shift();
        if (face === undefined) throw new Error("unscripted roll");
        return face;
      },
    };
  });
}

/** The table-state blob as stored, to check the die survives hibernation. */
async function storedTableState(table: string): Promise<Record<string, unknown>> {
  const stub = env.GAME_TABLE.get(env.GAME_TABLE.idFromName(table));
  return runInDurableObject(stub, async (_: GameTable, state) => {
    return (await state.storage.get("stones")) as Record<string, unknown>;
  });
}

describe("Junction routes", () => {
  it("lets any player roll the current die and broadcasts the pending roll", async () => {
    const table = "jn-roll";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player, username } = await seedAuth();
    await readState(table, fac);
    await scriptRolls(table, [7]);

    expect((await call(table, "/junction/roll", { token: player })).status).toBe(204);
    const state = await readState(table, fac);
    expect(state.die).toBe(10);
    expect(state.junction).toEqual({
      rolledBy: username,
      die: 10,
      face: 7,
      outcome: "flow",
      rerolls: 0,
      alteredSlots: [],
    });
    expect(state.messages.at(-1)?.content).toBe(`Junction — ${username} rolled: Flow — 7 on d10`);
    expect((await call(table, "/junction/roll", { token: player })).status).toBe(409);
  });

  it("runs the loop: step, roll, reroll, accept — the die resets and a critical adds a context aspect", async () => {
    const table = "jn-loop";
    const { token: fac, username: gm } = await seedAuth(undefined, { facilitator: true });
    await readState(table, fac);
    await scriptRolls(table, [3, 12]);

    expect((await call(table, "/die/step-up", { token: fac })).status).toBe(204);
    await call(table, "/junction/roll", { token: fac });
    await call(table, "/junction/reroll", { token: fac });
    expect((await call(table, "/junction/accept", { token: fac })).status).toBe(204);

    const state = await readState(table, fac);
    expect(state.die).toBe(10);
    expect(state.junction).toBeNull();
    expect(state.contextAspects).toMatchObject([
      { kind: "Boon", text: `Critical Flow from ${gm}'s Junction`, consumed: false },
    ]);
    expect(state.messages.map((m) => m.content)).toEqual([
      "Die stepped up — d10 → d12",
      `Junction — ${gm} rolled: Friction — 3 on d12`,
      "Reroll — Critical Flow — 12 on d12",
      "Junction accepted — Critical Flow — 12 on d12 (context boon added) — d12 → d10",
    ]);
    expect(await storedTableState(table)).toMatchObject({ die: 10, junction: null });
  });

  it("rejects a roll, leaving the die where it was", async () => {
    const table = "jn-reject";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    await call(table, "/die/step-down", { token: fac });
    await call(table, "/junction/roll", { token: fac });
    expect((await call(table, "/junction/reject", { token: fac })).status).toBe(204);

    const state = await readState(table, fac);
    expect(state.junction).toBeNull();
    expect(state.die).toBe(8);
    expect(state.messages.at(-1)?.content).toBe("Junction rejected — the roll is discarded");
    expect(await storedTableState(table)).toMatchObject({ die: 8 });
  });

  it("keeps reroll, accept, reject and the die steps facilitator-only, and maps refusals", async () => {
    const table = "jn-gates";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player } = await seedAuth();
    for (const path of ["/junction/reroll", "/junction/accept", "/junction/reject", "/die/step-up", "/die/step-down"]) {
      expect((await call(table, path, { token: player })).status).toBe(403);
    }
    for (const path of ["/junction/reroll", "/junction/accept", "/junction/reject"]) {
      expect((await call(table, path, { token: fac })).status).toBe(409);
    }
    for (let i = 0; i < 2; i++) await call(table, "/die/step-down", { token: fac });
    const atBottom = await call(table, "/die/step-down", { token: fac });
    expect(atBottom.status).toBe(409);
    expect(await atBottom.text()).toBe("The die is already at d6");
    expect((await call(table, "/stones/add", { token: fac, body: { kind: "Boon" } })).status).toBe(404);
  });
});

describe("Context boons and banes", () => {
  it("lets the facilitator rewrite the text of one, and refuses a blank", async () => {
    const table = "sa-edit";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    const id = await plant(table, fac, "Boon", "first wording");
    const res = await call(table, `/context-aspects/${id}/update`, {
      token: fac,
      body: { text: "second wording" },
    });
    expect(res.status).toBe(204);
    expect((await readState(table, fac)).contextAspects[0].text).toBe("second wording");

    const blank = await call(table, `/context-aspects/${id}/update`, {
      token: fac,
      body: { text: "  " },
    });
    expect(blank.status).toBe(400);
  });

  it("keeps edit and delete facilitator-only, and 404s an unknown one", async () => {
    const table = "sa-gates";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player } = await seedAuth();

    const id = await plant(table, fac, "Boon");
    for (const action of ["update", "delete"]) {
      const res = await call(table, `/context-aspects/${id}/${action}`, {
        token: player,
        body: { text: "x" },
      });
      expect(res.status).toBe(403);
    }
    const missing = crypto.randomUUID();
    for (const action of ["update", "delete"]) {
      const res = await call(table, `/context-aspects/${missing}/${action}`, {
        token: fac,
        body: { text: "x" },
      });
      expect(res.status).toBe(404);
    }
  });
});

describe("Move routes", () => {
  it("makes a Highlight at once, logs it, and keeps it open to undo against its log line", async () => {
    const table = "mv-highlight";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 2);

    const res = await call(table, "/moves/highlight", { token: ada.token, body: { aspect: "desire" } });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.die).toBe(12);
    expect(fateOf(state, 0)).toBe(1);
    const line = state.messages.at(-1);
    expect(line?.content).toBe("Highlight — Character 1: Desire — d10 → d12");
    expect(state.moves).toMatchObject([
      { kind: "highlight", slot: 0, aspect: "desire", actorName: ada.username, messageId: line?.id },
    ]);
    expect(await storedTableState(table)).toMatchObject({ die: 12, moves: state.moves });
  });

  it("routes every move to its rule", async () => {
    const table = "mv-all";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 4);
    const boonId = await plant(table, fac, "Boon", "a rope");

    expect((await call(table, "/moves/complicate", { token: ada.token, body: { aspect: "quest" } })).status).toBe(204);
    expect((await call(table, "/moves/create", { token: ada.token, body: { text: "a ladder" } })).status).toBe(204);
    expect(
      (await call(table, "/moves/highlight-context", { token: ada.token, body: { contextAspectId: boonId } })).status,
    ).toBe(204);

    let state = await readState(table, fac);
    expect(fateOf(state, 0)).toBe(5); // 4 + 2 - 1
    expect(state.die).toBe(12);
    expect(state.contextAspects.map((a) => [a.kind, a.text, a.consumed])).toEqual([
      ["Boon", "a rope", true],
      ["Bane", "", false],
      ["Boon", "a ladder", false],
    ]);
    expect(state.contextAspects[1].fromAspect).toEqual({ slot: 0, aspect: "quest" });
    expect(state.moves.map((m) => m.kind)).toEqual(["complicate", "create", "highlight-context"]);

    await scriptRolls(table, [2, 8]);
    await call(table, "/junction/roll", { token: ada.token });
    expect((await call(table, "/moves/alter", { token: ada.token })).status).toBe(204);
    state = await readState(table, fac);
    expect(state.junction).toMatchObject({ die: 12, face: 8, outcome: "flow", alteredSlots: [0] });
    expect(fateOf(state, 0)).toBe(3);
    expect(state.moves.map((m) => m.kind)).toEqual(["alter"]);
  });

  it("refuses every move but Alter once the Junction is rolled", async () => {
    const table = "mv-locked";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 3);
    await call(table, "/junction/roll", { token: ada.token });

    const locked = await call(table, "/moves/highlight", { token: ada.token, body: { aspect: "desire" } });
    expect(locked.status).toBe(409);
    expect(await locked.text()).toBe("Moves are locked once the Junction is rolled");
    expect((await call(table, "/moves/create", { token: ada.token, body: {} })).status).toBe(409);
    expect((await call(table, "/moves/alter", { token: ada.token })).status).toBe(204);
  });

  it("lets a player undo their own move and the facilitator anyone's; logs the undo", async () => {
    const table = "mv-undo";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 2);
    const bea = await seatPlayer(table, fac, 1, 2);
    await call(table, "/moves/highlight", { token: ada.token, body: { aspect: "desire" } });
    await call(table, "/moves/highlight", { token: bea.token, body: { aspect: "quest" } });
    const [adas, beas] = (await readState(table, fac)).moves;

    expect((await call(table, `/moves/${adas.id}/undo`, { token: bea.token })).status).toBe(403);
    expect((await call(table, `/moves/${adas.id}/undo`, { token: ada.token })).status).toBe(204);
    expect((await call(table, `/moves/${adas.id}/undo`, { token: ada.token })).status).toBe(404);
    expect((await call(table, `/moves/${beas.id}/undo`, { token: fac })).status).toBe(204);

    const state = await readState(table, fac);
    expect(state.die).toBe(10);
    expect([fateOf(state, 0), fateOf(state, 1)]).toEqual([2, 2]);
    expect(state.moves).toEqual([]);
    expect(state.messages.slice(-2).map((m) => m.content)).toEqual([
      "Highlight undone — Character 1 — d16 → d12",
      "Highlight undone — Character 2 — d12 → d10",
    ]);
  });

  it("closes undo when the Junction is rolled, and when a sheet changes hands", async () => {
    const table = "mv-undo-closed";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 2);
    await call(table, "/moves/highlight", { token: ada.token, body: { aspect: "desire" } });
    const [rolledAway] = (await readState(table, fac)).moves;
    await call(table, "/junction/roll", { token: ada.token });
    expect((await call(table, `/moves/${rolledAway.id}/undo`, { token: fac })).status).toBe(404);
    await call(table, "/junction/reject", { token: fac });

    await call(table, "/moves/highlight", { token: ada.token, body: { aspect: "desire" } });
    await call(table, "/characters/0/release", { token: ada.token });
    expect((await readState(table, fac)).moves).toEqual([]);
  });

  it("has retired the proposal routes", async () => {
    const table = "mv-retired";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const id = await plant(table, fac, "Boon");
    for (const path of [
      `/proposals/${crypto.randomUUID()}/accept`,
      `/proposals/${crypto.randomUUID()}/withdraw`,
      "/moves/add-detail",
      "/moves/use-context-boon",
      `/context-aspects/${id}/use`,
      `/context-aspects/${id}/unconsume`,
    ]) {
      expect((await call(table, path, { token: fac, body: {} })).status).toBe(404);
    }
  });
});

async function plant(
  table: string,
  fac: string,
  kind: "Boon" | "Bane",
  text = "a note",
): Promise<string> {
  await call(table, "/context-aspects", { token: fac, body: { kind, text } });
  const state = await readState(table, fac);
  const found = state.contextAspects.find((a) => a.text === text);
  if (!found) throw new Error("context aspect not created");
  return found.id;
}

/** Claim `slot` for a fresh player, write its three aspects, and give that
 * sheet `fate` boons. */
async function seatPlayer(
  table: string,
  fac: string,
  slot: number,
  fate: number,
): Promise<{ token: string; username: string }> {
  const player = await seedAuth();
  await claim(table, player.token, slot);
  await call(table, `/characters/${slot}/update`, {
    token: player.token,
    body: { archetype: "Smuggler", desire: "Freedom", quest: "Find the letter" },
  });
  if (fate !== 0) {
    await call(table, `/characters/${slot}/fate`, {
      token: fac,
      body: { delta: fate },
    });
  }
  return player;
}

function fateOf(state: import("../src/types").GameState, slot: number): number {
  return state.characters.find((c) => c.slot === slot)?.fate ?? -1;
}

describe("Sessions", () => {
  it("starting and ending a session touch nothing but the goal and history: the die, context boons and banes, and a pending Junction all survive", async () => {
    const table = "ss-inert";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 2);

    // Leave the die off the base, with everything pending.
    await call(table, "/die/step-up", { token: fac });
    await call(table, "/context-aspects", {
      token: fac,
      body: { kind: "Boon", text: "carries across" },
    });
    await call(table, "/moves/highlight", { token: ada.token, body: { aspect: "desire" } });
    await call(table, "/junction/roll", { token: ada.token });
    const before = await readState(table, fac);

    const started = await call(table, "/session/start", {
      token: fac,
      body: { goal: "Reach the archive" },
    });
    expect(started.status).toBe(204);
    let state = await readState(table, fac);
    expect(state.session?.goal).toBe("Reach the archive");
    expect(state.die).toBe(before.die);
    expect(state.contextAspects).toEqual(before.contextAspects);
    expect(state.junction).toEqual(before.junction);

    const ended = await call(table, "/session/end", { token: fac });
    expect(ended.status).toBe(204);
    state = await readState(table, fac);
    expect(state.session).toBeNull();
    expect(state.sessionHistory).toHaveLength(1);
    expect(state.die).toBe(before.die); // no reset
    expect(state.contextAspects).toEqual(before.contextAspects);
    expect(state.junction).toEqual(before.junction);
    expect(state.messages.at(-1)?.content).toBe(
      "Session ended — Reach the archive",
    );
  });
});
