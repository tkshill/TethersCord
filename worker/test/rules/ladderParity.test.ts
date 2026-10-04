import { describe, expect, it } from "vitest";
// The client's ladder, read from its source: the Elm suite cannot import the
// Worker's, so the pin lives on this side.
import dieElm from "../../../client/src/Die.elm?raw";
import { LADDER } from "../../src/rules/dice";

describe("the ladder in both languages", () => {
  it("matches Die.sizes in client/src/Die.elm", () => {
    const match = dieElm.match(/^sizes =\s*\n\s*\[([^\]]*)\]/m);
    expect(match, "Die.elm no longer has a one-line `sizes` list").not.toBeNull();
    const sizes = (match?.[1] ?? "").split(",").map((s) => Number(s.trim()));
    expect(sizes).toEqual([...LADDER]);
  });
});
