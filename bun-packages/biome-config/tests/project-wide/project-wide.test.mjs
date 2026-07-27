import { test } from "bun:test";
import { join } from "node:path";
import { lint, FIXTURES, ok } from "../helpers.mjs";

// Additive layer: base + project-wide. Needs the module graph, so lint from root.
const cwd = join(FIXTURES, "project-wide-project");
const r = lint(".", { cwd });
const has = (p, rule) => (r.byFile[p] ?? new Set()).has(rule);

test("project-wide · module-graph rules fire", () => {
  ok(has("bad-import.ts", "noUnresolvedImports"), "noUnresolvedImports on missing module");
});
