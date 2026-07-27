import { test } from "bun:test";
import { join } from "node:path";
import { lint, FIXTURES, ok } from "../helpers.mjs";

// CANARY (inverted test). Guards the HACK in layers/nuxt/overrides.jsonc that
// disables noUnusedVariables/noUnusedImports for *.vue because Biome does not
// see bindings used only inside <template>. Asserts the false positive STILL
// happens and FAILS once Biome understands template usage — the cue to remove the HACK.
const r = lint("Widget.vue", { cwd: join(FIXTURES, "canary/vue-unused") });

test("canary · Biome still reports template-only bindings as unused", () => {
  const falsePositive = r.rules.has("noUnusedImports") || r.rules.has("noUnusedVariables");
  ok(
    falsePositive,
    "Biome no longer flags template-only bindings as unused — the HACK in " +
      "layers/nuxt/overrides.jsonc disabling noUnusedVariables/noUnusedImports for *.vue " +
      "is OBSOLETE and can be removed.",
  );
});
