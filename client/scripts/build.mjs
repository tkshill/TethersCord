import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { cp, mkdir, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const clientDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = resolve(clientDir, "..");
const distDir = resolve(clientDir, "dist");

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

await cp(resolve(clientDir, "index.html"), resolve(distDir, "index.html"));

// Everything under client/public is copied verbatim to the asset root (fonts,
// and anything else static the SPA references by absolute path).
const publicDir = resolve(clientDir, "public");
if (existsSync(publicDir)) {
  await cp(publicDir, distDir, { recursive: true });
}

console.log("Client built in client/dist");
