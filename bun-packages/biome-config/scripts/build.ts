#!/usr/bin/env bun
// Assembles the consumable configs in dist/ from the authoring sources in layers/.
//
// Bun-native: the layer sources are JSONC (comments + examples), and Bun imports
// JSONC directly, so we parse each layer to an object and merge — no hand-rolled
// comment stripping or text slicing.
//
// Why not `bun build`? Bun's bundler emits JavaScript modules, but Biome's
// `extends` only accepts .json/.jsonc, so the bundler can't produce these
// configs. And why self-contained bundles at all? Biome resolves `extends` only
// ONE level deep — a config pulled in via `extends` has its own `extends`
// silently ignored, so each primary layer must inline what it needs. See:
//   https://github.com/biomejs/biome/issues/1867
//   https://github.com/biomejs/biome/discussions/8257

const ROOT = new URL("..", import.meta.url);
const DIST = new URL("dist/", ROOT);
const SCHEMA = "https://biomejs.dev/schemas/2.5.5/schema.json";

// Bun parses JSONC (comments + trailing commas) on import.
const load = async (rel: string): Promise<any> =>
  (await import(new URL(`layers/${rel}`, ROOT).href)).default;

const BASE_GROUPS = ["a11y", "complexity", "correctness", "performance", "security", "style", "suspicious", "nursery"];
const VUE_GROUPS = ["correctness", "performance", "style", "nursery"];

async function groupRules(dir: string, groups: string[]) {
  const rules: Record<string, unknown> = {};
  for (const g of groups) rules[g] = (await load(`${dir}/${g}.jsonc`)).linter.rules[g];
  return rules;
}

// base + vue additions, per group (vue rules append to / override the base group)
function mergeRules(base: Record<string, any>, extra: Record<string, any>) {
  const out: Record<string, any> = structuredClone(base);
  for (const g of Object.keys(extra)) out[g] = { ...(out[g] ?? {}), ...extra[g] };
  return out;
}

export async function build() {
  const settings = await load("base/settings.jsonc");
  const shared = { formatter: settings.formatter, assist: settings.assist, javascript: settings.javascript };

  const baseRules = await groupRules("base", BASE_GROUPS);
  const vueRules = mergeRules(baseRules, await groupRules("vue", VUE_GROUPS));
  const vueDomains = (await load("vue/domains.jsonc")).linter.domains;
  const nuxtOverrides = await load("nuxt/overrides.jsonc");

  const configs: Record<string, unknown> = {
    "base.json": { $schema: SCHEMA, ...shared, linter: { rules: baseRules } },
    "vue.json": { $schema: SCHEMA, ...shared, linter: { domains: vueDomains, rules: vueRules } },
    "nuxt.json": {
      $schema: SCHEMA,
      files: nuxtOverrides.files,
      ...shared,
      linter: { domains: vueDomains, rules: vueRules },
      overrides: nuxtOverrides.overrides,
    },
    "types.json": await load("types.jsonc"),
    "project-wide.json": await load("project-wide.jsonc"),
  };

  for (const [name, cfg] of Object.entries(configs)) {
    await Bun.write(new URL(name, DIST), `${JSON.stringify(cfg, null, 2)}\n`);
  }
  console.log(`Built dist/: ${Object.keys(configs).join(", ")}`);
}

if (import.meta.main) await build();
