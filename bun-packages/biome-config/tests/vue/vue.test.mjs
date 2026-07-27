import { test } from "bun:test";
import { join } from "node:path";
import { lintFile, DIST, FIXTURES, assertFires } from "../helpers.mjs";

// vue layer = base rules + the vue domain + Vue-specific rules.
test("vue · Vue-specific + inherited base rules fire", () => {
  const r = lintFile(join(FIXTURES, "vue/solo.vue"), join(DIST, "vue.json"));
  assertFires(r, "useVueMultiWordComponentNames", "(Vue-domain rule)");
  assertFires(r, "noVar", "(base rule, inherited by the vue layer)");
});
