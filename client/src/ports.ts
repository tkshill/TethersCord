// client/src/ports.ts
//
// One description of the Elm app's port surface and the two build-time globals,
// shared by main.ts (the `Elm.Main.init` return type), DiscordBridge.ts, and
// GameSocket.ts instead of each keeping its own hand-copied shape.

/** The ports `Ports.elm` declares, as they appear on `app.ports`. */
export type ElmPorts = {
  toDiscord: {
    // Elm sends plain objects; the bridge narrows on `.type`.
    subscribe: (handler: (msg: any) => void) => void;
  };
  fromDiscord: {
    send: (msg: unknown) => void;
  };
  wsGameState: {
    send: (msg: unknown) => void;
  };
  wsStatus: {
    send: (status: string) => void;
  };
};

/** The subset `GameSocket` touches. */
export type SocketPorts = Pick<ElmPorts, "wsGameState" | "wsStatus">;

declare global {
  interface Window {
    /** Injected into `index.html` at build time. */
    DISCORD_CLIENT_ID: string;
    /** Injected at build time; `""` in the single-origin deploy, so read it
     * with `|| window.location.origin`, not `??`. */
    BACKEND_BASE_URL: string;
  }
}
