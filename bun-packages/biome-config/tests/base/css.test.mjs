import { test } from "bun:test";
import { join } from "node:path";
import { lintFile, DIST, FIXTURES, assertFires } from "../helpers.mjs";

test("base · css", () => {
  const r = lintFile(join(FIXTURES, "base/css/violations.css"), join(DIST, "base.json"));
  for (const rule of ["noHexColors", "noDescendingSpecificity"]) assertFires(r, rule);
});
