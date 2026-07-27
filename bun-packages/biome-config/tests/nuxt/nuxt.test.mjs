import { test } from "bun:test";
import { join } from "node:path";
import { lint, FIXTURES, ok } from "../helpers.mjs";

// Lint the whole fixture project once so the Nuxt override globs
// (app/stores/**, app/components/**, **/*.config.ts, test/**, …) resolve
// against a realistic project root.
const cwd = join(FIXTURES, "nuxt-project");
const r = lint(".", { cwd });
const firedIn = (p) => r.byFile[p] ?? new Set();
const has = (p, rule) => firedIn(p).has(rule);

test("nuxt · overrides silence rules on their matched paths", () => {
  ok(!has("app/stores/counter.ts", "useExportsLast"), "pinia store: useExportsLast disabled");
  ok(!has("app/components/Foo_Bar.vue", "useFilenamingConvention"), "components: filenaming disabled");
  ok(!has("nuxt.config.ts", "noDefaultExport"), "*.config.ts: noDefaultExport disabled");
  ok(!has("nuxt.config.ts", "noProcessEnv"), "*.config.ts: noProcessEnv disabled");
  ok(!has("app/components/Widget.vue", "noUnusedVariables"), "*.vue: noUnusedVariables disabled");
  ok(!has("test/example.ts", "useNamingConvention"), "test/**: useNamingConvention disabled");
  ok(!has("app/app.vue", "useVueMultiWordComponentNames"), "app.vue: multi-word-name disabled");
});

test("nuxt · rules stay active where no override applies (controls)", () => {
  ok(has("app/util.ts", "noDefaultExport"), "noDefaultExport active outside config files");
  ok(has("app/util.ts", "noProcessEnv"), "noProcessEnv active outside config files");
  ok(has("app/components/Widget.vue", "useVueMultiWordComponentNames"), "multi-word-name active on ordinary components");
});
