import { DiscordSDK } from "@discord/embedded-app-sdk";
import { initDiscordBridge } from "./DiscordBridge";

declare const Elm: {
  Main: {
    init(options: {
      node: HTMLElement;
      flags: { apiBaseUrl: string; tableId: string };
    }): {
      ports: {
        toDiscord: { subscribe: (handler: (message: unknown) => void) => void };
        fromDiscord: { send: (message: unknown) => void };
        wsGameState: { send: (message: unknown) => void };
        wsStatus: { send: (status: string) => void };
      };
    };
  };
};

function getQueryParams(): Record<string, string> {
  const params = new URLSearchParams(window.location.search);
  const result: Record<string, string> = {};
  params.forEach((value, key) => {
    result[key] = value;
  });
  return result;
}

/**
 * A table has to outlive a single launch of the Activity. Discord mints a fresh
 * `instance_id` every time the Activity is opened, so keying on it gives every
 * session a brand new Durable Object and three blank character sheets. The
 * channel is the stable thing a group comes back to.
 */
function resolveTableId(
  discordSdk: DiscordSDK,
  queryParams: Record<string, string>,
): string {
  const channelId = discordSdk.channelId ?? queryParams["channel_id"];
  if (channelId) {
    const guildId = discordSdk.guildId ?? queryParams["guild_id"];
    return guildId ? `${guildId}-${channelId}` : channelId;
  }

  // Outside a Discord channel (a DM, or a plain browser tab) fall back to the
  // launch instance so at least one session hangs together.
  return queryParams["instance_id"] ?? "default-table";
}

async function main() {
  const discordSdk = new DiscordSDK((window as any).DISCORD_CLIENT_ID);
  await discordSdk.ready();

  const queryParams = getQueryParams();

  // `||` not `??`: BACKEND_BASE_URL is injected as "", which is not nullish, so
  // `??` would never reach the fallback.
  const apiBaseUrl = (window as any).BACKEND_BASE_URL || window.location.origin;
  const tableId = resolveTableId(discordSdk, queryParams);
  const root = document.getElementById("root");

  if (!root) {
    throw new Error('Missing required element with id "root"');
  }

  const app = Elm.Main.init({
    node: root,
    flags: {
      apiBaseUrl,
      tableId,
    },
  });

  await initDiscordBridge(discordSdk, app.ports, apiBaseUrl, tableId);
}

main().catch((err) => {
  console.error("Failed to start Activity:", err);
});
