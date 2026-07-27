import { test } from "bun:test";
import { join } from "node:path";
import { lintFile, DIST, FIXTURES, assertFires } from "../helpers.mjs";

test("base · json", () => {
  const r = lintFile(join(FIXTURES, "base/json/violations.json"), join(DIST, "base.json"));
  for (const rule of ["noDuplicateObjectKeys"]) assertFires(r, rule);
});
