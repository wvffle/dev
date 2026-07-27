import { test } from "bun:test";
import { join } from "node:path";
import { lint, FIXTURES, ok } from "../helpers.mjs";

// Additive layer: base + types. Type-aware rules require the Biome Scanner,
// so lint the whole fixture project from its root.
const cwd = join(FIXTURES, "types-project");
const r = lint(".", { cwd });
const has = (p, rule) => (r.byFile[p] ?? new Set()).has(rule);

test("types · type-aware rules fire", () => {
  ok(has("await-thenable.ts", "useAwaitThenable"), "useAwaitThenable on `await 42`");
  ok(has("base-to-string.ts", "noBaseToString"), "noBaseToString on object interpolation");
});
