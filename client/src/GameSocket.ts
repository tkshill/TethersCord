// client/src/GameSocket.ts

import type { SocketPorts } from "./ports";

const MAX_RECONNECT_DELAY_MS = 10000;
const MAX_RECONNECT_ATTEMPTS = 8;

/** Policy violation — the server rejected our credentials, so retrying is futile. */
const CLOSE_UNAUTHORIZED = 1008;

export type GameSocketHandle = {
  close: () => void;
};

export function connectGameSocket(
  backendBaseUrl: string,
  tableId: string,
  sessionToken: string,
  ports: SocketPorts,
): GameSocketHandle {
  const url = buildWsUrl(backendBaseUrl, tableId);
  let attempt = 0;
  let socket: WebSocket | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let disposed = false;

  const open = () => {
    if (disposed) return;

    socket = new WebSocket(url, ["bearer", sessionToken]);

    socket.addEventListener("open", () => {
      attempt = 0;
      ports.wsStatus.send("connected");
    });

    socket.addEventListener("message", (event) => {
      try {
        ports.wsGameState.send(JSON.parse(event.data as string));
      } catch (error) {
        console.error("Failed to parse game state push", error);
      }
    });

    socket.addEventListener("close", (event) => {
      // A rejected handshake surfaces here. Reconnecting would replay the same
      // rejected credentials every ten seconds, forever.
      if (event.code === CLOSE_UNAUTHORIZED) {
        console.error("Game socket rejected: session token was not accepted");
        ports.wsStatus.send("rejected");
        return;
      }
      ports.wsStatus.send("reconnecting");
      scheduleReconnect();
    });

    socket.addEventListener("error", () => socket?.close());
  };

  const scheduleReconnect = () => {
    if (disposed) return;

    if (attempt >= MAX_RECONNECT_ATTEMPTS) {
      console.error("Game socket gave up after", attempt, "attempts");
      ports.wsStatus.send("offline");
      return;
    }

    const delay = Math.min(1000 * 2 ** attempt, MAX_RECONNECT_DELAY_MS);
    attempt += 1;
    timer = setTimeout(open, delay);
  };

  open();

  return {
    close: () => {
      disposed = true;
      if (timer !== null) clearTimeout(timer);
      socket?.close();
    },
  };
}

function buildWsUrl(backendBaseUrl: string, tableId: string): string {
  const url = new URL(
    `/api/table/${encodeURIComponent(tableId)}/connect`,
    backendBaseUrl || window.location.origin,
  );
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  return url.toString();
}
