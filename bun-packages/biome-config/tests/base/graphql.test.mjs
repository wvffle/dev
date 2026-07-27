import { test } from "bun:test";
import { join } from "node:path";
import { lintFile, DIST, FIXTURES, assertFires } from "../helpers.mjs";

test("base · graphql", () => {
  const r = lintFile(join(FIXTURES, "base/graphql/violations.graphql"), join(DIST, "base.json"));
  for (const rule of ["noDuplicateGraphqlOperationName"]) assertFires(r, rule);
});
