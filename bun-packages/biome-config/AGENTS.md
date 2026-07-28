# AGENTS.md — @wvffle/biome-config

## Commands

| Step | Command |
|------|---------|
| Build | `bun run build` (runs `scripts/build.ts`) |
| Test | `bun test` (preload rebuilds `dist/` first) |
| Publish | `npm publish` — `prepublishOnly` runs build automatically |

## Architecture

- **Bun-only package.** Everything depends on Bun's native JSONC import (`bun build` can't be used — it emits JS modules but Biome `extends` only accepts `.json`/`.jsonc`).
- **Primary layers** (pick one): `base` (TS/JS rules), `vue` (base + Vue domain + Vue rules), `nuxt` (vue + Nuxt file patterns + overrides).
- **Capability layers** (opt-in, extend alongside a primary layer): `types` (type-aware rules like `noBaseToString`), `project-wide` (cross-file rules like `noImportCycles`). These are thin — they do not include `base`. Enabling them spins up the Biome Scanner over the whole project.
- **Self-contained bundles:** Biome resolves `extends` only **one level deep**. Each primary layer inlines `base` rules — the build script merges them. A `nuxt → vue → base` chain would silently drop most rules.
- **Source → output:** `layers/` (commented JSONC with examples) → `scripts/build.ts` imports each layer via Bun, merges → writes comment-free `dist/` configs. `dist/` is git-ignored.

## How tests work

- Tests run the **real `@biomejs/biome` CLI** against fixture files, asserting which rules fire.
- `tests/setup.mjs` preload rebuilds `dist/` before every test run.
- Fixture directories (`nuxt-project/`, `types-project/`, `project-wide-project/`) each contain their own `biome.json` — tests use `lintFile()` to run from each fixture's own directory, preventing Biome from scanning sibling fixtures.
- `tests/helpers.mjs` exports `lint()`, `lintFile()`, `assertFires()`, `assertQuiet()`.

## Layer source structure

- `layers/base/{settings,a11y,complexity,correctness,nursery,performance,security,style,suspicious}.jsonc` — rule definitions and settings
- `layers/vue/{correctness,domains,nursery,performance,style}.jsonc` — Vue additions (appends to / overrides base groups)
- `layers/nuxt/overrides.jsonc` — Nuxt file patterns + override rules
- `layers/types.jsonc`, `layers/project-wide.jsonc` — capability layers (thin, include their own `extends`)

## Gotchas

- **Never run `bun build`** — it emits JS modules. The build must be `bun scripts/build.ts`.
- **Never edit `dist/` directly** — it's regenerated from `layers/`.
- **Adding a new rule:** edit the appropriate `layers/{base,vue}/{group}.jsonc`, not `dist/`.
- **Adding a new layer:** add a source in `layers/`, then add an entry in `scripts/build.ts` and `exports` in `package.json`.
- **`trustedDependencies`** in package.json lets Biome download its platform binary. Don't remove it.
