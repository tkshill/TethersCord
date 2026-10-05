import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { build } from "esbuild";
import { unstable_readConfig } from "wrangler";

const clientDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(clientDir, "..");
const distDir = resolve(clientDir, "dist");

// `--env staging` builds for that Wrangler environment; no flag is production.
// The Discord client id comes from the environment's `vars` in wrangler.jsonc,
// so each application's id is written once, beside the Worker that uses it.
const { values: args } = parseArgs({ options: { env: { type: "string" } } });
const config = unstable_readConfig({
  config: resolve(repoRoot, "wrangler.jsonc"),
  env: args.env,
});
const clientId = config.vars?.DISCORD_CLIENT_ID;
if (typeof clientId !== "string" || !/^\d{17,20}$/.test(clientId)) {
  throw new Error(
    `DISCORD_CLIENT_ID for ${args.env ?? "production"} in wrangler.jsonc is ` +
      `not a Discord application id: ${JSON.stringify(clientId)}`,
  );
}

// Go to the package, not node_modules/.bin. The elm package ships bin/elm as a
// JS placeholder and swaps in a native binary during its install script, so
// pnpm's shim -- written from the placeholder -- tries to run the binary through
// `node` and dies. The package path is correct under both pnpm and npm, and it
// also makes `node client/scripts/build.mjs` work outside a package script,
// where node_modules/.bin is not on PATH.
const localElm = resolve(repoRoot, "node_modules/elm/bin/elm");
const elm = existsSync(localElm) ? localElm : "elm";

await rm(distDir, { recursive: true, force: true });
await mkdir(distDir, { recursive: true });

execFileSync(
  elm,
  ["make", "src/Main.elm", "--optimize", "--output", "dist/elm.js"],
  {
    cwd: clientDir,
    stdio: "inherit",
  },
);

await build({
  absWorkingDir: clientDir,
  entryPoints: ["src/main.ts"],
  bundle: true,
  format: "esm",
  platform: "browser",
  target: "es2022",
  outfile: "dist/main.js",
  sourcemap: true,
});

const indexHtml = await readFile(resolve(clientDir, "index.html"), "utf8");
await writeFile(
  resolve(distDir, "index.html"),
  indexHtml.replaceAll("%DISCORD_CLIENT_ID%", clientId),
);

// Everything under client/public is copied verbatim to the asset root (fonts,
// and anything else static the SPA references by absolute path).
const publicDir = resolve(clientDir, "public");
if (existsSync(publicDir)) {
  await cp(publicDir, distDir, { recursive: true });
}

console.log(`Client built in client/dist (${args.env ?? "production"})`);
