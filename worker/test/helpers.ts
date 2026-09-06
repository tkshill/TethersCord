import { SELF, env } from "cloudflare:test";

const HOUR = 60 * 60 * 1000;

/**
 * Insert a `sessions_auth` row so a bearer token resolves to a real user. Pass
 * `facilitator: true` to also add a `facilitators` row, which is what
 * `getAuthFromToken` / `inferRole` read to decide the role.
 */
export async function seedAuth(
  token: string = crypto.randomUUID(),
  {
    userId = `user-${token}`,
    username = userId,
    facilitator = false,
    expiresAt = Date.now() + HOUR,
  }: {
    userId?: string;
    username?: string;
    facilitator?: boolean;
    expiresAt?: number;
  } = {},
): Promise<{ token: string; userId: string; username: string }> {
  await env.DB.prepare(
    `INSERT INTO sessions_auth (session_token, discord_user_id, discord_username, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(token, userId, username, Date.now(), expiresAt)
    .run();

  if (facilitator) {
    await env.DB.prepare(
      `INSERT INTO facilitators (discord_user_id, created_at) VALUES (?, ?)`,
    )
      .bind(userId, Date.now())
      .run();
  }

  return { token, userId, username };
}

type CallOptions = { token?: string; body?: unknown; method?: string };

/**
 * Call a table route through the real Worker entry (index.ts → GameTable DO).
 * `tableId` picks the Durable Object; use a fresh one per test so isolated
 * storage does not have to be relied on for separation.
 */
export function call(
  tableId: string,
  path: string,
  { token, body, method }: CallOptions = {},
): Promise<Response> {
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers["Content-Type"] = "application/json";

  return SELF.fetch(`https://tetherscord.test/api/table/${tableId}${path}`, {
    method: method ?? "POST",
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
}

/** GET the whole broadcast `GameState` for a table. */
export async function readState(
  tableId: string,
  token: string,
): Promise<import("../src/types").GameState> {
  const res = await call(tableId, "/messages", { token, method: "GET" });
  if (res.status !== 200) {
    throw new Error(`readState ${tableId} -> ${res.status}`);
  }
  return res.json();
}

/** Claim a slot for the caller and return the refreshed state. */
export async function claim(
  tableId: string,
  token: string,
  slot: number,
): Promise<void> {
  const res = await call(tableId, `/characters/${slot}/claim`, { token });
  if (res.status !== 204) {
    throw new Error(`claim slot ${slot} -> ${res.status}`);
  }
}
