// client/src/DiscordBridge.ts

import { DiscordSDK, type Types } from "@discord/embedded-app-sdk";
import type { BackendAuthResult } from "../../worker/src/types";
import { connectGameSocket, type GameSocketHandle } from "./GameSocket";

type OAuthScopes = Types.OAuthScopes;

type ElmPorts = {
  toDiscord: {
    subscribe: (handler: (msg: any) => void) => void;
  };
  fromDiscord: {
    send: (msg: any) => void;
  };
  wsGameState: {
    send: (msg: unknown) => void;
  };
  wsStatus: {
    send: (status: string) => void;
  };
};

export async function initDiscordBridge(
  discordSdk: DiscordSDK,
  ports: ElmPorts,
  backendBaseUrl: string,
  tableId: string,
): Promise<void> {
  // Re-authorizing must not leave the previous socket (and its reconnect loop)
  // running in the background.
  let socket: GameSocketHandle | null = null;

  ports.toDiscord.subscribe(async (msg: any) => {
    if (msg.type === "Authorize") {
      // Elm sends strings, we trust they are valid scopes and cast:
      const scopes = ((msg.scopes as string[]) ?? [
        "identify",
      ]) as OAuthScopes[];

      try {
        const authCode = await runDiscordAuthorize(discordSdk, scopes);
        const backendResult = await exchangeCodeWithBackend(
          backendBaseUrl,
          authCode,
        );

        // Completes the Activity handshake. Without this the SDK stays
        // unauthenticated and every privileged command (setActivity,
        // getChannel, participant subscriptions) fails.
        await discordSdk.commands.authenticate({
          access_token: backendResult.accessToken,
        });

        socket?.close();
        socket = connectGameSocket(
          backendBaseUrl,
          tableId,
          backendResult.sessionToken,
          ports,
        );

        ports.fromDiscord.send({
          type: "BackendAuthResult",
          data: backendResult,
        });
      } catch (error) {
        console.error("Authorize flow failed", error);
        ports.fromDiscord.send({
          type: "AuthFailed",
          data: { message: describeError(error) },
        });
      }
    }
  });
}

function describeError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function apiUrl(backendBaseUrl: string, path: string): string {
  if (!backendBaseUrl || backendBaseUrl === window.location.origin) {
    return path;
  }

  return `${backendBaseUrl}${path}`;
}

async function runDiscordAuthorize(
  discordSdk: DiscordSDK,
  scopes: OAuthScopes[],
): Promise<string> {
  const response = await discordSdk.commands.authorize({
    client_id: (window as any).DISCORD_CLIENT_ID,
    response_type: "code",
    state: "",
    scope: scopes,
    prompt: "none",
  });

  return response.code;
}

async function exchangeCodeWithBackend(
  backendBaseUrl: string,
  code: string,
): Promise<BackendAuthResult> {
  const response = await fetch(
    apiUrl(backendBaseUrl, "/api/oauth/discord/exchange"),
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code }),
    },
  );

  if (!response.ok) {
    throw new Error(`Backend auth exchange failed: ${await response.text()}`);
  }

  return (await response.json()) as BackendAuthResult;
}
