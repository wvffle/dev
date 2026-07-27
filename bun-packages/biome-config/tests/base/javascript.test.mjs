import { test } from "bun:test";
import { join } from "node:path";
import { lintFile, DIST, FIXTURES, assertFires } from "../helpers.mjs";

test("base · javascript", () => {
  const r = lintFile(join(FIXTURES, "base/js/violations.js"), join(DIST, "base.json"));
  for (const rule of ["noVar", "useConst", "noParameterAssign", "useTemplate", "noUselessElse"]) assertFires(r, rule);
});
