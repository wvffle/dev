import { test } from "bun:test";
import { join } from "node:path";
import { lintFile, DIST, FIXTURES, assertFires } from "../helpers.mjs";

test("tests · all rules", () => {
  const r = lintFile(join(FIXTURES, "tests-project/violations.ts"), join(DIST, "tests.json"));
  // suspicious
  for (const rule of ["noDuplicateTestHooks", "noExportsInTest", "noFocusedTests", "noSkippedTests"]) assertFires(r, rule);
  // complexity
  assertFires(r, "noExcessiveNestedTestSuites");
  // nursery
  for (const rule of [
    "noConditionalExpect",
    "noIdenticalTestTitle",
    "useConsistentTestIt",
    "useExpect",
    "useTestHooksInOrder",
    "useTestHooksOnTop",
    "noPlaywrightElementHandle",
    "noPlaywrightEval",
    "noPlaywrightForceOption",
    "noPlaywrightMissingAwait",
    "noPlaywrightNetworkidle",
    "noPlaywrightPagePause",
    "noPlaywrightUselessAwait",
    "noPlaywrightWaitForNavigation",
    "noPlaywrightWaitForSelector",
    "noPlaywrightWaitForTimeout",
    "usePlaywrightValidDescribeCallback",
  ]) assertFires(r, rule);
});
