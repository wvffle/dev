// Shared test helpers. Runs the real Biome CLI against fixtures and exposes
// which lint rules fired, so tests can assert a layer's behavior.
//
// Tests run against the BUILT configs in dist/ — the same artifacts consumers
// extend. The `bun test` preload (tests/setup.mjs) builds dist/ automatically.
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, basename, join, isAbsolute } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
export const ROOT = join(HERE, "..");
export const DIST = join(ROOT, "dist");
export const FIXTURES = join(HERE, "fixtures");

// Prefer a locally-installed Biome; fall back to one on PATH.
const localBin = join(ROOT, "node_modules", ".bin", process.platform === "win32" ? "biome.cmd" : "biome");
const BIOME = existsSync(localBin) ? localBin : "biome";

// Run `biome lint` and return the set of rule names / categories that fired.
//   opts.config : path to a config file passed via --config-path (optional;
//                 omit to let Biome auto-discover a biome.json in `cwd`)
//   opts.cwd    : working directory to run from (default: package root)
export function lint(targets, opts = {}) {
  const list = Array.isArray(targets) ? targets : [targets];
  const args = ["lint", "--reporter=json", "--colors=off", "--max-diagnostics=1000"];
  if (opts.config) args.push(`--config-path=${isAbsolute(opts.config) ? opts.config : join(ROOT, opts.config)}`);
  const res = spawnSync(BIOME, [...args, ...list], { cwd: opts.cwd ?? ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (res.error) throw res.error;
  let json;
  try {
    json = JSON.parse(res.stdout);
  } catch {
    throw new Error(`Could not parse Biome JSON output.\nstdout:\n${res.stdout?.slice(0, 400)}\nstderr:\n${res.stderr?.slice(0, 400)}`);
  }
  const diags = json.diagnostics ?? [];
  const cats = diags.map((d) => d.category ?? "");
  return {
    rules: new Set(cats.map((c) => c.split("/").pop()).filter(Boolean)),
    categories: new Set(cats),
    byFile: diags.reduce((m, d) => {
      const p = d.location?.path?.file ?? d.location?.path ?? "?";
      (m[p] ??= new Set()).add((d.category ?? "").split("/").pop());
      return m;
    }, {}),
    diagnostics: diags,
  };
}

// Lint a single fixture file from ITS OWN directory, so Biome's project scan
// never wanders into sibling fixtures (which carry their own biome.json and
// would trip Biome's "nested root configuration" check).
export function lintFile(fixtureAbsPath, config) {
  return lint(basename(fixtureAbsPath), { config, cwd: dirname(fixtureAbsPath) });
}

// Framework-agnostic assertion: throwing fails the test under any runner.
export function ok(cond, message) {
  if (!cond) throw new Error(message);
}

export function assertFires(result, rule, extra = "") {
  ok(
    result.rules.has(rule),
    `expected rule "${rule}" to fire but it did not. Fired: [${[...result.rules].sort().join(", ")}]. ${extra}`,
  );
}

export function assertQuiet(result, rule, extra = "") {
  ok(!result.rules.has(rule), `expected rule "${rule}" NOT to fire, but it did. ${extra}`);
}
