// noDuplicateTestHooks — duplicate beforeEach
describe("duplicate hooks", () => {
  beforeEach(() => {});
  beforeEach(() => {});
});

// noExportsInTest — export in test file
export function testHelper() {
  return 42;
}

// noFocusedTests — .only
describe.only("focused describe", () => {
  test.only("focused test", () => {});
});

// noSkippedTests — .skip / .fixme
describe.skip("skipped describe", () => {
  test.skip("skipped test", () => {});
  test.fixme("fixme test", () => {});
});

// noExcessiveNestedTestSuites — 7 levels
describe("level1", () => {
  describe("level2", () => {
    describe("level3", () => {
      describe("level4", () => {
        describe("level5", () => {
          describe("level6", () => {
            describe("level7", () => {});
          });
        });
      });
    });
  });
});

// noConditionalExpect — expect inside if
test("conditional expect", async ({ page }) => {
  if (true) {
    await expect(page).toHaveTitle("Title");
  }
});

// noIdenticalTestTitle — duplicate titles
it("duplicate title", () => {});
it("duplicate title", () => {});

// useConsistentTestIt — using test() instead of it() (config expects "it")
test("should use it instead", () => {});

// useExpect — no assertions
test("no assertion", async ({ page }) => {
  await page.goto("/");
  await page.click("button");
});

// useTestHooksInOrder — out of order (beforeEach before beforeAll)
describe("out of order hooks", () => {
  beforeEach(() => {});
  beforeAll(() => {});
});

// useTestHooksOnTop — hook after test
describe("hooks on bottom", () => {
  it("does something", () => {});
  beforeEach(() => {});
});

// noPlaywrightElementHandle — page.$() / page.$$()
test("element handle", async ({ page }) => {
  const button = await page.$("button");
  const buttons = await page.$$(".btn");
});

// noPlaywrightEval — page.$eval() / page.$$eval()
test("page eval", async ({ page }) => {
  await page.$eval(".foo", (el) => el.textContent);
  const texts = await page.$$eval(".foo", (els) => els.map((el) => el.textContent));
});

// noPlaywrightForceOption — { force: true }
test("force option", async ({ page }) => {
  await page.locator("button").click({ force: true });
});

// noPlaywrightMissingAwait — missing await on expect
test("missing await", async ({ page }) => {
  expect(page.getByRole("button")).toBeVisible();
});

// noPlaywrightNetworkidle — networkidle option
test("networkidle", async ({ page }) => {
  await page.waitForLoadState("networkidle");
  await page.goto("https://example.com", { waitUntil: "networkidle" });
});

// noPlaywrightPagePause — page.pause()
test("page pause", async ({ page }) => {
  await page.pause();
});

// noPlaywrightUselessAwait — awaiting non-promise
test("useless await", async ({ page }) => {
  await page.locator(".my-element");
  await expect(1).toBe(1);
});

// noPlaywrightWaitForNavigation — page.waitForNavigation()
test("wait for navigation", async ({ page }) => {
  await page.waitForNavigation();
  await page.waitForNavigation({ waitUntil: "networkidle" });
});

// noPlaywrightWaitForSelector — page.waitForSelector()
test("wait for selector", async ({ page }) => {
  await page.waitForSelector(".submit-button");
});

// noPlaywrightWaitForTimeout — page.waitForTimeout()
test("wait for timeout", async ({ page }) => {
  await page.waitForTimeout(5000);
});

// usePlaywrightValidDescribeCallback — async describe / callback with params
test.describe("async describe", async () => {});
test.describe("describe with param", (done) => {});
