import { test } from "bun:test";
import { join } from "node:path";
import { lintFile, FIXTURES, ok } from "../helpers.mjs";

// CANARY (inverted test). Guards the FIXME in layers/vue/nursery.jsonc that
// disables useVueConsistentDefinePropsDeclaration because the rule is broken
// as of Biome 2.5.5 (https://github.com/biomejs/biome/issues/8682). The rule
// claims to enforce type-based defineProps but fires on valid type-based
// declarations like defineProps<Props>() — especially when defineModel is also
// present in the same <script setup>.
//
// The fixture (PhoneInput.vue) uses defineProps<Props>() which IS the
// type-based style the rule demands. If the rule fires, it is still broken.
// When Biome fixes it, this test will fail, signaling the FIXME can be removed.
const r = lintFile(
  join(FIXTURES, "canary/define-props-declaration/PhoneInput.vue"),
  join(FIXTURES, "canary/define-props-declaration/biome.json"),
);

test("canary · useVueConsistentDefinePropsDeclaration still fires on valid type-based defineProps", () => {
  const broken = r.rules.has("useVueConsistentDefinePropsDeclaration");
  ok(
    broken,
    "Biome no longer fires useVueConsistentDefinePropsDeclaration on valid " +
      "type-based defineProps<Props>() — the FIXME in layers/vue/nursery.jsonc " +
      "can be resolved: re-enable the rule with 'level: error'.",
  );
});
