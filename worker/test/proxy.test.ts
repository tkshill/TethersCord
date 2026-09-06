import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

// The Worker entry (worker/src/index.ts) in front of the Durable Object: it
// validates the table id, rewrites the path, and stamps `?tableId=` from the
// path segment so a client cannot point one table's DO at another table's rows.
describe("worker proxy (index.ts)", () => {
  it("404s a path outside /api", async () => {
    const res = await SELF.fetch("https://tetherscord.test/anything");
    expect(res.status).toBe(404);
  });

  it("rejects a table id that fails TABLE_ID_PATTERN", async () => {
    const res = await SELF.fetch(
      "https://tetherscord.test/api/table/not a valid id/messages",
      { headers: { Authorization: "Bearer nope" } },
    );
    expect(res.status).toBe(400);
    expect(await res.text()).toBe("Invalid table id");
  });

  it("forwards a well-formed table id to the DO, which then requires auth", async () => {
    const res = await SELF.fetch(
      "https://tetherscord.test/api/table/guild-channel/messages",
    );
    expect(res.status).toBe(401);
  });
});
