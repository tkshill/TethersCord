// worker/src/index.ts

import type { ExecutionContext } from "@cloudflare/workers-types";
import type { Env } from "./types";
import { GameTable } from "./GameTable";
import { pruneOldMessages } from "./maintenance";
import { handleDiscordExchange, pruneExpiredSessions } from "./oauth-discord";

export { GameTable };

/** Discord instance/channel ids are snowflakes; keep the DO namespace tight. */
const TABLE_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

export default {
  async fetch(
    request: Request,
    env: Env,
    _ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);

    if (
      url.pathname === "/api/oauth/discord/exchange" &&
      request.method === "POST"
    ) {
      return handleDiscordExchange(request, env);
    }

    if (url.pathname.startsWith("/api/table/")) {
      const [, , , tableId, ...rest] = url.pathname.split("/");

      if (!TABLE_ID_PATTERN.test(tableId ?? "")) {
        return new Response("Invalid table id", { status: 400 });
      }

      const objectId = env.GAME_TABLE.idFromName(tableId);
      const stub = env.GAME_TABLE.get(objectId);

      const proxyUrl = new URL(request.url);
      proxyUrl.pathname = "/" + rest.join("/");

      // The table id comes from the path, which routed us to this object.
      // Overwrite (never append) so a client-supplied `tableId` cannot make one
      // table's Durable Object read or write another table's rows.
      proxyUrl.searchParams.set("tableId", tableId);
      proxyUrl.searchParams.delete("sessionId");

      return stub.fetch(new Request(proxyUrl, request));
    }

    return new Response("Not found", { status: 404 });
  },

  async scheduled(
    _event: unknown,
    env: Env,
    ctx: ExecutionContext,
  ): Promise<void> {
    ctx.waitUntil(pruneExpiredSessions(env));
    ctx.waitUntil(pruneOldMessages(env));
  },
};
