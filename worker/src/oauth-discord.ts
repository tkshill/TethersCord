// worker/src/oauth-discord.ts

import type { Env, BackendAuthResult, Role } from "./types";

type DiscordTokenResponse = {
  access_token: string;
  token_type: string;
  expires_in: number;
  refresh_token: string;
  scope: string;
};

type DiscordUser = {
  id: string;
  username: string;
  global_name?: string | null;
  discriminator: string;
  avatar: string | null;
};

/** Fallback session lifetime when Discord does not tell us one. */
const DEFAULT_SESSION_TTL_MS = 60 * 60 * 1000;

export async function handleDiscordExchange(
  request: Request,
  env: Env,
): Promise<Response> {
  let code: unknown;
  try {
    ({ code } = (await request.json()) as { code?: unknown });
  } catch {
    return new Response("Invalid JSON body", { status: 400 });
  }

  if (typeof code !== "string" || !code) {
    return new Response("Missing authorization code", { status: 400 });
  }

  // No `redirect_uri`: codes minted by the Embedded App SDK's `authorize`
  // command are not issued against one, and sending an unregistered value
  // makes Discord reject the exchange with invalid_grant.
  const tokenRes = await fetch("https://discord.com/api/oauth2/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      client_id: env.DISCORD_CLIENT_ID,
      client_secret: env.DISCORD_CLIENT_SECRET,
      grant_type: "authorization_code",
      code,
    }),
  });

  if (!tokenRes.ok) {
    // Log the upstream detail, but do not reflect it back to the caller.
    console.error("Discord token exchange failed", {
      status: tokenRes.status,
      body: await tokenRes.text(),
    });
    return new Response("Discord token exchange failed", { status: 400 });
  }

  const tokenData = (await tokenRes.json()) as DiscordTokenResponse;
  const accessToken = tokenData.access_token;

  const userRes = await fetch("https://discord.com/api/users/@me", {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!userRes.ok) {
    return new Response("Failed to fetch user from Discord", { status: 400 });
  }

  const user = (await userRes.json()) as DiscordUser;

  const username =
    user.global_name ??
    (user.discriminator === "0"
      ? user.username
      : `${user.username}#${user.discriminator}`);

  const role = await inferRole(env, user.id);

  const sessionToken = crypto.randomUUID();
  const ttlMs =
    typeof tokenData.expires_in === "number" && tokenData.expires_in > 0
      ? tokenData.expires_in * 1000
      : DEFAULT_SESSION_TTL_MS;
  const expiresAt = Date.now() + ttlMs;

  await env.DB.prepare(
    `
    INSERT INTO sessions_auth (session_token, discord_user_id, discord_username, created_at, expires_at)
    VALUES (?, ?, ?, ?, ?)
  `,
  )
    .bind(sessionToken, user.id, username, Date.now(), expiresAt)
    .run();

  const result: BackendAuthResult = {
    userId: user.id,
    username,
    role,
    sessionToken,
    expiresAt,
    // Returned so the client can finish the handshake with
    // `discordSdk.commands.authenticate({ access_token })`.
    accessToken,
  };

  return new Response(JSON.stringify(result), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

/** Invoked from the hourly cron trigger; sessions_auth is append-only otherwise. */
export async function pruneExpiredSessions(env: Env): Promise<void> {
  await env.DB.prepare(`DELETE FROM sessions_auth WHERE expires_at <= ?`)
    .bind(Date.now())
    .run();
}

async function inferRole(env: Env, discordUserId: string): Promise<Role> {
  if (
    env.BOOTSTRAP_FACILITATOR_ID &&
    env.BOOTSTRAP_FACILITATOR_ID === discordUserId
  ) {
    return "facilitator";
  }

  const dmRow = await env.DB.prepare(
    `
    SELECT 1 FROM facilitators
    WHERE discord_user_id = ?
    LIMIT 1
  `,
  )
    .bind(discordUserId)
    .first<{ "1": number } | null>();

  return dmRow ? "facilitator" : "player";
}
