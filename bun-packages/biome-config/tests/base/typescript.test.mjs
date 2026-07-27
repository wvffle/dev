import { test } from "bun:test";
import { join } from "node:path";
import { lintFile, DIST, FIXTURES, assertFires } from "../helpers.mjs";

test("base · typescript", () => {
  const r = lintFile(join(FIXTURES, "base/ts/violations.ts"), join(DIST, "base.json"));
  for (const rule of ["noNonNullAssertion", "useConsistentArrayType", "useExportType", "useImportType"]) assertFires(r, rule);
});
