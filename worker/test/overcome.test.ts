import { describe, expect, it } from "vitest";
import { call, claim, readState, seedAuth } from "./helpers";

// The Overcome loop (roadmap section 26.2): prepare the pool, one player
// rolls, optional Alter Fate rerolls, the facilitator accepts or rejects.
// Tests act through the routes and observe through the broadcast snapshot and
// the message log. The draw is random, so a test that needs a known result
// shapes the pool first through the facilitator's `/stones/{add,remove}`:
// `[Boon, Boon]` can only ever draw a pair of Boons.

/** Leave the pool with exactly these stones (base pool is 2 Boon, 2 Bane). */
async function shapePool(
  table: string,
  fac: string,
  boons: number,
  banes: number,
): Promise<void> {
  const state = await readState(table, fac);
  const have = {
    Boon: state.stonePool.filter((s) => s === "Boon").length,
    Bane: state.stonePool.filter((s) => s === "Bane").length,
  };
  for (const [kind, want] of [
    ["Boon", boons],
    ["Bane", banes],
  ] as const) {
    for (let i = have[kind]; i < want; i++) {
      await call(table, "/stones/add", { token: fac, body: { kind } });
    }
    for (let i = have[kind]; i > want; i--) {
      await call(table, "/stones/remove", { token: fac, body: { kind } });
    }
  }
}

describe("Overcome: rolling", () => {
  it("lets any player roll: two stones are drawn, the pool is untouched, and the roll is logged", async () => {
    const table = "oc-roll";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player, username } = await seedAuth();

    const before = await readState(table, fac);
    const res = await call(table, "/overcome/roll", { token: player });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.stonePool).toEqual(before.stonePool);
    expect(state.overcome).toMatchObject({
      rolledBy: username,
      rerolls: 0,
      alteredSlots: [],
    });
    expect(state.overcome?.stones).toHaveLength(2);
    expect(state.messages.at(-1)?.content).toMatch(
      new RegExp(`^Overcome — ${username} rolled: (Boon|Bane), (Boon|Bane)$`),
    );
  });

  it("refuses a second roll while one is pending", async () => {
    const table = "oc-roll-twice";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player } = await seedAuth();

    expect((await call(table, "/overcome/roll", { token: player })).status).toBe(
      204,
    );
    const first = (await readState(table, fac)).overcome;

    const second = await call(table, "/overcome/roll", { token: fac });
    expect(second.status).toBe(409);
    expect((await readState(table, fac)).overcome).toEqual(first);
  });
});

describe("Overcome: accepting", () => {
  it("resets the pool to two Boon and two Bane and clears the pending roll", async () => {
    const table = "oc-accept-reset";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player } = await seedAuth();

    await shapePool(table, fac, 5, 1);
    await call(table, "/overcome/roll", { token: player });

    const res = await call(table, "/overcome/accept", { token: fac });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.overcome).toBeNull();
    expect(state.stonePool.filter((s) => s === "Boon")).toHaveLength(2);
    expect(state.stonePool.filter((s) => s === "Bane")).toHaveLength(2);
  });

  it("creates a session boon, credited to the roller, when two Boons were drawn", async () => {
    const table = "oc-accept-boon-pair";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player, username } = await seedAuth();

    await shapePool(table, fac, 4, 0);
    await call(table, "/overcome/roll", { token: player });
    await call(table, "/overcome/accept", { token: fac });

    const state = await readState(table, fac);
    expect(state.sessionAspects).toHaveLength(1);
    expect(state.sessionAspects[0]).toMatchObject({
      kind: "Boon",
      createdByName: username,
      consumed: false,
    });
    expect(state.sessionAspects[0].text).not.toBe("");
    expect(state.messages.at(-1)?.content).toBe(
      "Overcome accepted — Boon, Boon (session boon added)",
    );
  });

  it("creates a session bane when two Banes were drawn", async () => {
    const table = "oc-accept-bane-pair";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player } = await seedAuth();

    await shapePool(table, fac, 0, 4);
    await call(table, "/overcome/roll", { token: player });
    await call(table, "/overcome/accept", { token: fac });

    const state = await readState(table, fac);
    expect(state.sessionAspects).toHaveLength(1);
    expect(state.sessionAspects[0]).toMatchObject({ kind: "Bane" });
    expect(state.messages.at(-1)?.content).toBe(
      "Overcome accepted — Bane, Bane (session bane added)",
    );
  });

  it("creates nothing when the draw was mixed", async () => {
    const table = "oc-accept-mixed";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player } = await seedAuth();

    await shapePool(table, fac, 1, 1);
    await call(table, "/overcome/roll", { token: player });
    await call(table, "/overcome/accept", { token: fac });

    const state = await readState(table, fac);
    expect(state.sessionAspects).toHaveLength(0);
    expect(state.messages.at(-1)?.content).toMatch(
      /^Overcome accepted — (Boon, Bane|Bane, Boon)$/,
    );
  });

  it("is facilitator-only, and 409s when nothing is pending", async () => {
    const table = "oc-accept-gates";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player } = await seedAuth();

    expect((await call(table, "/overcome/accept", { token: fac })).status).toBe(
      409,
    );
    await call(table, "/overcome/roll", { token: player });
    expect(
      (await call(table, "/overcome/accept", { token: player })).status,
    ).toBe(403);
    expect((await readState(table, fac)).overcome).not.toBeNull();
  });
});

describe("Overcome: rejecting", () => {
  it("discards the pending roll and changes nothing else", async () => {
    const table = "oc-reject";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player } = await seedAuth();

    await shapePool(table, fac, 4, 0);
    await call(table, "/overcome/roll", { token: player });
    const before = await readState(table, fac);

    const res = await call(table, "/overcome/reject", { token: fac });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.overcome).toBeNull();
    expect(state.stonePool).toEqual(before.stonePool); // not reset
    expect(state.sessionAspects).toHaveLength(0); // a pair creates nothing on reject
    expect(state.messages.at(-1)?.content).toBe(
      "Overcome rejected — the roll is discarded",
    );

    // The table can roll again.
    expect((await call(table, "/overcome/roll", { token: player })).status).toBe(
      204,
    );
  });

  it("is facilitator-only, and 409s when nothing is pending", async () => {
    const table = "oc-reject-gates";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player } = await seedAuth();

    expect((await call(table, "/overcome/reject", { token: fac })).status).toBe(
      409,
    );
    await call(table, "/overcome/roll", { token: player });
    expect(
      (await call(table, "/overcome/reject", { token: player })).status,
    ).toBe(403);
  });
});

describe("Overcome: the facilitator's free reroll", () => {
  it("redraws from the pool, counts the reroll, and logs it", async () => {
    const table = "oc-reroll";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player } = await seedAuth();

    await shapePool(table, fac, 4, 0);
    await call(table, "/overcome/roll", { token: player });
    const before = await readState(table, fac);

    const res = await call(table, "/overcome/reroll", { token: fac });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.overcome?.rerolls).toBe(1);
    expect(state.overcome?.stones).toEqual(["Boon", "Boon"]);
    expect(state.overcome?.rolledBy).toBe(before.overcome?.rolledBy);
    expect(state.stonePool).toEqual(before.stonePool);
    expect(state.messages.at(-1)?.content).toBe("Reroll — Boon, Boon");
  });

  it("is facilitator-only, and 409s when nothing is pending", async () => {
    const table = "oc-reroll-gates";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player } = await seedAuth();

    expect((await call(table, "/overcome/reroll", { token: fac })).status).toBe(
      409,
    );
    await call(table, "/overcome/roll", { token: player });
    expect(
      (await call(table, "/overcome/reroll", { token: player })).status,
    ).toBe(403);
  });
});

describe("Session boons and banes", () => {
  async function plant(
    table: string,
    fac: string,
    kind: "Boon" | "Bane",
    text = "a note",
  ): Promise<string> {
    await call(table, "/session-aspects", { token: fac, body: { kind, text } });
    const state = await readState(table, fac);
    const found = state.sessionAspects.find((a) => a.text === text);
    if (!found) throw new Error("session aspect not created");
    return found.id;
  }

  it("lets the facilitator use one directly: the pool gains that kind, and it is marked consumed rather than deleted", async () => {
    const table = "sa-use-bane";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    const id = await plant(table, fac, "Bane", "the guard suspects");
    const res = await call(table, `/session-aspects/${id}/use`, { token: fac });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.stonePool.filter((s) => s === "Bane")).toHaveLength(3);
    expect(state.sessionAspects).toHaveLength(1);
    expect(state.sessionAspects[0]).toMatchObject({ id, consumed: true });
    expect(state.messages.at(-1)?.content).toBe(
      "Session bane used — the guard suspects",
    );
  });

  it("refuses to use a consumed one a second time", async () => {
    const table = "sa-use-twice";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    const id = await plant(table, fac, "Boon");
    await call(table, `/session-aspects/${id}/use`, { token: fac });
    const again = await call(table, `/session-aspects/${id}/use`, { token: fac });
    expect(again.status).toBe(409);

    const state = await readState(table, fac);
    expect(state.stonePool.filter((s) => s === "Boon")).toHaveLength(3); // once only
  });

  it("lets the facilitator unconsume one to correct a mistake, without touching the pool", async () => {
    const table = "sa-unconsume";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    const id = await plant(table, fac, "Boon");
    await call(table, `/session-aspects/${id}/use`, { token: fac });
    const res = await call(table, `/session-aspects/${id}/unconsume`, {
      token: fac,
    });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.sessionAspects[0].consumed).toBe(false);
    expect(state.stonePool.filter((s) => s === "Boon")).toHaveLength(3);

    const notConsumed = await call(table, `/session-aspects/${id}/unconsume`, {
      token: fac,
    });
    expect(notConsumed.status).toBe(409);
  });

  it("lets the facilitator rewrite the text of one, and refuses a blank", async () => {
    const table = "sa-edit";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });

    const id = await plant(table, fac, "Boon", "first wording");
    const res = await call(table, `/session-aspects/${id}/update`, {
      token: fac,
      body: { text: "second wording" },
    });
    expect(res.status).toBe(204);
    expect((await readState(table, fac)).sessionAspects[0].text).toBe(
      "second wording",
    );

    const blank = await call(table, `/session-aspects/${id}/update`, {
      token: fac,
      body: { text: "  " },
    });
    expect(blank.status).toBe(400);
  });

  it("keeps use, unconsume and edit facilitator-only, and 404s an unknown one", async () => {
    const table = "sa-gates";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const { token: player } = await seedAuth();

    const id = await plant(table, fac, "Boon");
    for (const action of ["use", "unconsume", "update"]) {
      const res = await call(table, `/session-aspects/${id}/${action}`, {
        token: player,
        body: { text: "x" },
      });
      expect(res.status).toBe(403);
    }

    const missing = crypto.randomUUID();
    for (const action of ["use", "unconsume", "update"]) {
      const res = await call(table, `/session-aspects/${missing}/${action}`, {
        token: fac,
        body: { text: "x" },
      });
      expect(res.status).toBe(404);
    }
  });
});

/** Claim `slot` for a fresh player and give that sheet `fate` boons. */
async function seatPlayer(
  table: string,
  fac: string,
  slot: number,
  fate: number,
): Promise<{ token: string; username: string }> {
  const player = await seedAuth();
  await claim(table, player.token, slot);
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

async function firstProposalId(table: string, token: string): Promise<string> {
  const id = (await readState(table, token)).proposals[0]?.id;
  if (!id) throw new Error("no proposal queued");
  return id;
}

describe("Move: Highlight", () => {
  it("queues a proposal and logs it, without moving anything until the facilitator accepts", async () => {
    const table = "mv-hl-propose";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 2);

    const res = await call(table, "/moves/highlight", { token: ada.token });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.proposals).toHaveLength(1);
    expect(state.proposals[0]).toMatchObject({ kind: "highlight", slot: 0 });
    expect(fateOf(state, 0)).toBe(2);
    expect(state.stonePool).toHaveLength(4);
    expect(state.messages.at(-1)?.content).toBe(
      "Character 1 proposes Highlight",
    );
  });

  it("on accept moves one boon from the player to the pool, and logs it", async () => {
    const table = "mv-hl-accept";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 2);

    await call(table, "/moves/highlight", { token: ada.token });
    const id = await firstProposalId(table, fac);
    const res = await call(table, `/proposals/${id}/accept`, { token: fac });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.proposals).toHaveLength(0);
    expect(fateOf(state, 0)).toBe(1);
    expect(state.stonePool.filter((s) => s === "Boon")).toHaveLength(3);
    expect(state.messages.at(-1)?.content).toBe(
      "Highlight accepted — Character 1 pays 1 boon, the pool gains a Boon",
    );
  });

  it("on reject changes nothing and logs the rejection", async () => {
    const table = "mv-hl-reject";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 2);

    await call(table, "/moves/highlight", { token: ada.token });
    const id = await firstProposalId(table, fac);
    await call(table, `/proposals/${id}/reject`, { token: fac });

    const state = await readState(table, fac);
    expect(state.proposals).toHaveLength(0);
    expect(fateOf(state, 0)).toBe(2);
    expect(state.stonePool).toHaveLength(4);
    expect(state.messages.at(-1)?.content).toBe(
      "Highlight rejected — Character 1",
    );
  });

  it("cannot be proposed without a boon to pay, or without a claimed sheet", async () => {
    const table = "mv-hl-cost";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const broke = await seatPlayer(table, fac, 0, 0);
    const { token: unseated } = await seedAuth();

    expect(
      (await call(table, "/moves/highlight", { token: broke.token })).status,
    ).toBe(400);
    expect(
      (await call(table, "/moves/highlight", { token: unseated })).status,
    ).toBe(400);
    expect((await readState(table, fac)).proposals).toHaveLength(0);
  });

  it("is checked again on accept: 409, proposal stays queued, nothing moves", async () => {
    const table = "mv-hl-recheck";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 1);

    await call(table, "/moves/highlight", { token: ada.token });
    // The boon is taken away while the proposal waits.
    await call(table, "/characters/0/fate", { token: fac, body: { delta: -1 } });

    const id = await firstProposalId(table, fac);
    const res = await call(table, `/proposals/${id}/accept`, { token: fac });
    expect(res.status).toBe(409);

    const state = await readState(table, fac);
    expect(state.proposals).toHaveLength(1);
    expect(state.stonePool).toHaveLength(4);
  });

  it("is not blocked by a pending Overcome — the frozen pool is a table rule", async () => {
    const table = "mv-hl-not-locked";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 1);

    await call(table, "/overcome/roll", { token: ada.token });
    await call(table, "/moves/highlight", { token: ada.token });
    const id = await firstProposalId(table, fac);
    expect(
      (await call(table, `/proposals/${id}/accept`, { token: fac })).status,
    ).toBe(204);
    expect((await readState(table, fac)).stonePool).toHaveLength(5);
  });
});

describe("Move: Complicate", () => {
  it("queues a proposal naming another character, and logs it", async () => {
    const table = "mv-cx-propose";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 0);
    await seatPlayer(table, fac, 1, 0);

    const res = await call(table, "/moves/complicate", {
      token: ada.token,
      body: { targetSlot: 1 },
    });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.proposals[0]).toMatchObject({
      kind: "complicate",
      slot: 0,
      targetSlot: 1,
    });
    expect(state.messages.at(-1)?.content).toBe(
      "Character 1 proposes Complicate on Character 2",
    );
  });

  it("needs a claimed sheet and a valid target that is not your own character", async () => {
    const table = "mv-cx-validate";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 0);
    const { token: unseated } = await seedAuth();

    const post = (token: string, body: unknown) =>
      call(table, "/moves/complicate", { token, body });
    expect((await post(unseated, { targetSlot: 1 })).status).toBe(400);
    expect((await post(ada.token, {})).status).toBe(400);
    expect((await post(ada.token, { targetSlot: 0 })).status).toBe(400); // self
    expect((await post(ada.token, { targetSlot: 3 })).status).toBe(400);
    expect((await post(ada.token, { targetSlot: 1.5 })).status).toBe(400);
    expect((await readState(table, fac)).proposals).toHaveLength(0);
  });

  it("on accept pays the target character two boons and the suggester nothing", async () => {
    const table = "mv-cx-accept";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 1);
    await seatPlayer(table, fac, 1, 0);

    await call(table, "/moves/complicate", {
      token: ada.token,
      body: { targetSlot: 1 },
    });
    const id = await firstProposalId(table, fac);
    expect(
      (await call(table, `/proposals/${id}/accept`, { token: fac })).status,
    ).toBe(204);

    const state = await readState(table, fac);
    expect(state.proposals).toHaveLength(0);
    expect(fateOf(state, 0)).toBe(1); // suggester unchanged
    expect(fateOf(state, 1)).toBe(2);
    expect(state.messages.at(-1)?.content).toBe(
      "Complicate accepted — Character 2 gains 2 boons (suggested by Character 1)",
    );
  });

  it("on reject changes nothing and logs the rejection; it has no per-session limit", async () => {
    const table = "mv-cx-reject";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 0);
    await seatPlayer(table, fac, 1, 0);

    for (let i = 0; i < 2; i++) {
      await call(table, "/moves/complicate", {
        token: ada.token,
        body: { targetSlot: 1 },
      });
      const id = await firstProposalId(table, fac);
      await call(table, `/proposals/${id}/reject`, { token: fac });
    }

    const state = await readState(table, fac);
    expect(state.proposals).toHaveLength(0);
    expect(fateOf(state, 1)).toBe(0);
    expect(state.messages.at(-1)?.content).toBe(
      "Complicate rejected — Character 1",
    );
  });

  it("drops the proposal if the target releases their sheet before it is resolved", async () => {
    const table = "mv-cx-target-gone";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 0);
    const bea = await seatPlayer(table, fac, 1, 0);

    await call(table, "/moves/complicate", {
      token: ada.token,
      body: { targetSlot: 1 },
    });
    const id = await firstProposalId(table, fac);
    await call(table, "/characters/1/release", { token: bea.token });

    const res = await call(table, `/proposals/${id}/accept`, { token: fac });
    expect(res.status).not.toBe(204);
    expect(fateOf(await readState(table, fac), 0)).toBe(0);
  });
});

describe("Move: Add Detail", () => {
  it("queues a proposal carrying the player's suggested text, or none, and logs it", async () => {
    const table = "mv-ad-propose";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 2);

    expect(
      (
        await call(table, "/moves/add-detail", {
          token: ada.token,
          body: { text: "the door is barred from inside" },
        })
      ).status,
    ).toBe(204);
    expect(
      (await call(table, "/moves/add-detail", { token: ada.token, body: {} }))
        .status,
    ).toBe(204);

    const state = await readState(table, fac);
    expect(state.proposals).toHaveLength(2);
    expect(state.proposals[0]).toMatchObject({
      kind: "add-detail",
      slot: 0,
      text: "the door is barred from inside",
    });
    expect(state.proposals[1].text).toBeNull(); // asking the facilitator for one
    expect(fateOf(state, 0)).toBe(2); // nothing paid yet
    expect(state.messages.at(-1)?.content).toBe(
      "Character 1 proposes Add Detail",
    );
  });

  it("cannot be proposed without a boon to pay, or without a claimed sheet", async () => {
    const table = "mv-ad-cost";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const broke = await seatPlayer(table, fac, 0, 0);
    const { token: unseated } = await seedAuth();

    expect(
      (await call(table, "/moves/add-detail", { token: broke.token, body: {} }))
        .status,
    ).toBe(400);
    expect(
      (await call(table, "/moves/add-detail", { token: unseated, body: {} }))
        .status,
    ).toBe(400);
  });

  it("on accept costs the player one boon and creates a session boon with the facilitator's wording", async () => {
    const table = "mv-ad-accept";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 2);

    await call(table, "/moves/add-detail", {
      token: ada.token,
      body: { text: "the door is barred" },
    });
    const id = await firstProposalId(table, fac);
    const res = await call(table, `/proposals/${id}/accept`, {
      token: fac,
      body: { text: "the door is barred from the inside" },
    });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.proposals).toHaveLength(0);
    expect(fateOf(state, 0)).toBe(1);
    expect(state.sessionAspects).toHaveLength(1);
    expect(state.sessionAspects[0]).toMatchObject({
      kind: "Boon",
      text: "the door is barred from the inside",
      createdByName: ada.username,
      consumed: false,
    });
    expect(state.messages.at(-1)?.content).toBe(
      "Add Detail accepted — Character 1 pays 1 boon: the door is barred from the inside",
    );
  });

  it("falls back to the player's suggestion, then to a default, when the facilitator writes nothing", async () => {
    const table = "mv-ad-fallback";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 2);

    await call(table, "/moves/add-detail", {
      token: ada.token,
      body: { text: "a suggestion" },
    });
    await call(table, `/proposals/${await firstProposalId(table, fac)}/accept`, {
      token: fac,
    });
    await call(table, "/moves/add-detail", { token: ada.token, body: {} });
    await call(table, `/proposals/${await firstProposalId(table, fac)}/accept`, {
      token: fac,
      body: { text: "  " },
    });

    const aspects = (await readState(table, fac)).sessionAspects;
    expect(aspects[0].text).toBe("a suggestion");
    expect(aspects[1].text).toBe(`Detail from ${ada.username}`);
  });

  it("is checked again on accept, and a rejection changes nothing", async () => {
    const table = "mv-ad-recheck";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 1);

    await call(table, "/moves/add-detail", { token: ada.token, body: {} });
    await call(table, "/characters/0/fate", { token: fac, body: { delta: -1 } });
    const id = await firstProposalId(table, fac);
    expect(
      (await call(table, `/proposals/${id}/accept`, { token: fac })).status,
    ).toBe(409);
    expect((await readState(table, fac)).proposals).toHaveLength(1);

    await call(table, `/proposals/${id}/reject`, { token: fac });
    const state = await readState(table, fac);
    expect(state.sessionAspects).toHaveLength(0);
    expect(state.messages.at(-1)?.content).toBe(
      "Add Detail rejected — Character 1",
    );
  });
});

describe("Move: Alter Fate", () => {
  /** A table with a pending Overcome (pool shaped to all Boons) and two players. */
  async function pendingOvercome(table: string) {
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 3);
    const bea = await seatPlayer(table, fac, 1, 3);
    await shapePool(table, fac, 4, 0);
    await call(table, "/overcome/roll", { token: ada.token });
    return { fac, ada, bea };
  }

  it("queues a proposal during a pending Overcome and logs it, taking no boons yet", async () => {
    const table = "mv-al-propose";
    const { fac, ada } = await pendingOvercome(table);

    const res = await call(table, "/moves/alter", { token: ada.token });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.proposals[0]).toMatchObject({ kind: "alter", slot: 0 });
    expect(fateOf(state, 0)).toBe(3);
    expect(state.messages.at(-1)?.content).toBe("Character 1 proposes Alter Fate");
  });

  it("cannot be proposed without a pending Overcome, a sheet, or two boons", async () => {
    const table = "mv-al-gates";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const rich = await seatPlayer(table, fac, 0, 3);
    const poor = await seatPlayer(table, fac, 1, 1);
    const { token: unseated } = await seedAuth();

    // No Overcome yet.
    expect((await call(table, "/moves/alter", { token: rich.token })).status).toBe(
      409,
    );

    await call(table, "/overcome/roll", { token: rich.token });
    expect((await call(table, "/moves/alter", { token: unseated })).status).toBe(
      400,
    );
    expect((await call(table, "/moves/alter", { token: poor.token })).status).toBe(
      400,
    );
    expect((await readState(table, fac)).proposals).toHaveLength(0);
  });

  it("allows only one pending Alter Fate at a time", async () => {
    const table = "mv-al-one-at-a-time";
    const { ada, bea } = await pendingOvercome(table);

    expect((await call(table, "/moves/alter", { token: ada.token })).status).toBe(
      204,
    );
    expect((await call(table, "/moves/alter", { token: bea.token })).status).toBe(
      409,
    );
  });

  it("on accept costs two boons, rerolls the stones, and marks the player as having altered", async () => {
    const table = "mv-al-accept";
    const { fac, ada } = await pendingOvercome(table);

    await call(table, "/moves/alter", { token: ada.token });
    const id = await firstProposalId(table, fac);
    const res = await call(table, `/proposals/${id}/accept`, { token: fac });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.proposals).toHaveLength(0);
    expect(fateOf(state, 0)).toBe(1);
    expect(state.overcome).toMatchObject({ rerolls: 1, alteredSlots: [0] });
    expect(state.overcome?.stones).toEqual(["Boon", "Boon"]);
    expect(state.messages.at(-1)?.content).toBe(
      "Alter Fate accepted — Character 1 pays 2 boons, rerolled: Boon, Boon",
    );
  });

  it("allows each player one Alter Fate per Overcome, but another player may still alter", async () => {
    const table = "mv-al-once-each";
    const { fac, ada, bea } = await pendingOvercome(table);

    await call(table, "/moves/alter", { token: ada.token });
    await call(table, `/proposals/${await firstProposalId(table, fac)}/accept`, {
      token: fac,
    });
    // Plenty of boons left: the limit is the once-per-Overcome rule, not cost.
    await call(table, "/characters/0/fate", { token: fac, body: { delta: 3 } });

    expect((await call(table, "/moves/alter", { token: ada.token })).status).toBe(
      409,
    );
    expect((await call(table, "/moves/alter", { token: bea.token })).status).toBe(
      204,
    );
  });

  it("a rejected Alter Fate costs nothing and does not use up the attempt", async () => {
    const table = "mv-al-reject";
    const { fac, ada } = await pendingOvercome(table);

    await call(table, "/moves/alter", { token: ada.token });
    await call(table, `/proposals/${await firstProposalId(table, fac)}/reject`, {
      token: fac,
    });

    const state = await readState(table, fac);
    expect(fateOf(state, 0)).toBe(3);
    expect(state.overcome).toMatchObject({ rerolls: 0, alteredSlots: [] });
    expect(state.messages.at(-1)?.content).toBe("Alter Fate rejected — Character 1");
    expect((await call(table, "/moves/alter", { token: ada.token })).status).toBe(
      204,
    );
  });

  it("is checked again on accept: 409 when the player can no longer pay, proposal stays queued", async () => {
    const table = "mv-al-recheck";
    const { fac, ada } = await pendingOvercome(table);

    await call(table, "/moves/alter", { token: ada.token });
    await call(table, "/characters/0/fate", { token: fac, body: { delta: -2 } });

    const id = await firstProposalId(table, fac);
    expect(
      (await call(table, `/proposals/${id}/accept`, { token: fac })).status,
    ).toBe(409);
    const state = await readState(table, fac);
    expect(state.proposals).toHaveLength(1);
    expect(state.overcome?.rerolls).toBe(0);
  });

  it("withdraws a queued Alter Fate when the Overcome is rejected or accepted, without charging for it", async () => {
    const table = "mv-al-resolve";
    const { fac, ada } = await pendingOvercome(table);

    await call(table, "/moves/alter", { token: ada.token });
    await call(table, "/overcome/reject", { token: fac });
    let state = await readState(table, fac);
    expect(state.proposals).toHaveLength(0);
    expect(fateOf(state, 0)).toBe(3);

    await call(table, "/overcome/roll", { token: ada.token });
    await call(table, "/moves/alter", { token: ada.token });
    await call(table, "/overcome/accept", { token: fac });
    state = await readState(table, fac);
    expect(state.proposals).toHaveLength(0);
    expect(fateOf(state, 0)).toBe(3);
  });

  it("starts every Overcome with nobody having altered", async () => {
    const table = "mv-al-fresh";
    const { fac, ada } = await pendingOvercome(table);

    await call(table, "/moves/alter", { token: ada.token });
    await call(table, `/proposals/${await firstProposalId(table, fac)}/accept`, {
      token: fac,
    });
    await call(table, "/overcome/accept", { token: fac });
    await call(table, "/characters/0/fate", { token: fac, body: { delta: 3 } });

    await call(table, "/overcome/roll", { token: ada.token });
    const state = await readState(table, fac);
    expect(state.overcome?.alteredSlots).toEqual([]);
    expect((await call(table, "/moves/alter", { token: ada.token })).status).toBe(
      204,
    );
  });
});

describe("Move: Use Session Boon", () => {
  async function tableWithSessionBoon(table: string, kind: "Boon" | "Bane" = "Boon") {
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 0);
    await call(table, "/session-aspects", {
      token: fac,
      body: { kind, text: "the guard is distracted" },
    });
    const id = (await readState(table, fac)).sessionAspects[0].id;
    return { fac, ada, id };
  }

  it("queues a proposal and logs it; nothing is spent until the facilitator accepts", async () => {
    const table = "mv-us-propose";
    const { fac, ada, id } = await tableWithSessionBoon(table);

    const res = await call(table, "/moves/use-session-boon", {
      token: ada.token,
      body: { sessionAspectId: id },
    });
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.proposals[0]).toMatchObject({
      kind: "use-session-boon",
      slot: 0,
      sessionAspectId: id,
    });
    expect(state.sessionAspects[0].consumed).toBe(false);
    expect(state.stonePool).toHaveLength(4);
    expect(state.messages.at(-1)?.content).toBe(
      "Character 1 proposes Use Session Boon",
    );
  });

  it("on accept marks it consumed (kept, not deleted) and adds a Boon to the pool", async () => {
    const table = "mv-us-accept";
    const { fac, ada, id } = await tableWithSessionBoon(table);

    await call(table, "/moves/use-session-boon", {
      token: ada.token,
      body: { sessionAspectId: id },
    });
    const res = await call(
      table,
      `/proposals/${await firstProposalId(table, fac)}/accept`,
      { token: fac },
    );
    expect(res.status).toBe(204);

    const state = await readState(table, fac);
    expect(state.proposals).toHaveLength(0);
    expect(state.sessionAspects).toHaveLength(1);
    expect(state.sessionAspects[0].consumed).toBe(true);
    expect(state.stonePool.filter((s) => s === "Boon")).toHaveLength(3);
    expect(state.messages.at(-1)?.content).toBe(
      "Use Session Boon accepted — Character 1 spends the guard is distracted; the pool gains a Boon",
    );
  });

  it("on reject changes nothing and logs the rejection", async () => {
    const table = "mv-us-reject";
    const { fac, ada, id } = await tableWithSessionBoon(table);

    await call(table, "/moves/use-session-boon", {
      token: ada.token,
      body: { sessionAspectId: id },
    });
    await call(table, `/proposals/${await firstProposalId(table, fac)}/reject`, {
      token: fac,
    });

    const state = await readState(table, fac);
    expect(state.sessionAspects[0].consumed).toBe(false);
    expect(state.stonePool).toHaveLength(4);
    expect(state.messages.at(-1)?.content).toBe(
      "Use Session Boon rejected — Character 1",
    );
  });

  it("refuses an unknown, consumed, already-proposed, or Bane one, and needs a sheet", async () => {
    const table = "mv-us-refuse";
    const { fac, ada, id } = await tableWithSessionBoon(table);
    const { token: unseated } = await seedAuth();
    const use = (token: string, sessionAspectId: string) =>
      call(table, "/moves/use-session-boon", { token, body: { sessionAspectId } });

    expect((await use(unseated, id)).status).toBe(400);
    expect((await use(ada.token, crypto.randomUUID())).status).toBe(404);
    expect((await use(ada.token, "")).status).toBe(400);

    expect((await use(ada.token, id)).status).toBe(204);
    expect((await use(ada.token, id)).status).toBe(409); // already proposed

    await call(table, `/proposals/${await firstProposalId(table, fac)}/reject`, {
      token: fac,
    });
    await call(table, `/session-aspects/${id}/use`, { token: fac });
    expect((await use(ada.token, id)).status).toBe(409); // consumed

    await call(table, "/session-aspects", {
      token: fac,
      body: { kind: "Bane", text: "a looming threat" },
    });
    const bane = (await readState(table, fac)).sessionAspects.find(
      (a) => a.kind === "Bane",
    );
    expect((await use(ada.token, bane!.id)).status).toBe(400); // banes: facilitator only
  });

  it("is checked again on accept: 409 if it was consumed meanwhile, and the proposal stays queued", async () => {
    const table = "mv-us-recheck";
    const { fac, ada, id } = await tableWithSessionBoon(table);

    await call(table, "/moves/use-session-boon", {
      token: ada.token,
      body: { sessionAspectId: id },
    });
    await call(table, `/session-aspects/${id}/use`, { token: fac });
    const poolAfterDirectUse = (await readState(table, fac)).stonePool;

    const res = await call(
      table,
      `/proposals/${await firstProposalId(table, fac)}/accept`,
      { token: fac },
    );
    expect(res.status).toBe(409);
    const state = await readState(table, fac);
    expect(state.proposals).toHaveLength(1);
    expect(state.stonePool).toEqual(poolAfterDirectUse); // spent once, not twice
  });
});

describe("Sessions", () => {
  it("starting and ending a session touch nothing but the goal and history: pool, proposals, session boons and banes, and a pending Overcome all survive", async () => {
    const table = "ss-inert";
    const { token: fac } = await seedAuth(undefined, { facilitator: true });
    const ada = await seatPlayer(table, fac, 0, 2);

    // Leave the pool below the old top-up floor, with everything pending.
    await shapePool(table, fac, 1, 0);
    await call(table, "/session-aspects", {
      token: fac,
      body: { kind: "Boon", text: "carries across" },
    });
    await call(table, "/moves/highlight", { token: ada.token });
    await call(table, "/overcome/roll", { token: ada.token });
    const before = await readState(table, fac);

    const started = await call(table, "/session/start", {
      token: fac,
      body: { goal: "Reach the archive" },
    });
    expect(started.status).toBe(204);
    let state = await readState(table, fac);
    expect(state.session?.goal).toBe("Reach the archive");
    expect(state.stonePool).toEqual(before.stonePool);
    expect(state.proposals).toEqual(before.proposals);
    expect(state.sessionAspects).toEqual(before.sessionAspects);
    expect(state.overcome).toEqual(before.overcome);

    const ended = await call(table, "/session/end", { token: fac });
    expect(ended.status).toBe(204);
    state = await readState(table, fac);
    expect(state.session).toBeNull();
    expect(state.sessionHistory).toHaveLength(1);
    expect(state.stonePool).toEqual(before.stonePool); // no top-up
    expect(state.proposals).toEqual(before.proposals);
    expect(state.sessionAspects).toEqual(before.sessionAspects);
    expect(state.overcome).toEqual(before.overcome);
    expect(state.messages.at(-1)?.content).toBe(
      "Session ended — Reach the archive",
    );
  });
});
