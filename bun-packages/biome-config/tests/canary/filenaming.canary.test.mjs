import { test } from "bun:test";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { lintFile, FIXTURES, ok } from "../helpers.mjs";

// CANARY (inverted test). Guards the HACK in layers/nuxt/overrides.jsonc that
// turns useFilenamingConvention OFF for components. The intent was to enforce
// PascalCase component filenames *including all-uppercase acronyms* (e.g.
// VSC.vue), which Biome could not express. Asserts the workaround is STILL
// needed and FAILS the moment Biome handles every case.
//
// Each file is linted individually (from its own directory, using the fixture's
// biome.json) so the result never depends on how Biome formats paths in a
// directory report. Desired behavior under
// { strictCase: false, filenameCases: ["PascalCase"] }:
//   MyButton.vue  accepted (ordinary PascalCase)
//   VSC.vue       accepted (all-uppercase acronym — the "UPPERCASE filename case")
//   mybutton.vue  rejected (lowercase)
const dir = join(FIXTURES, "canary/filenaming");
const flagged = (f) => {
  const path = join(dir, f);
  ok(existsSync(path), `fixture missing: ${path} (cannot evaluate the canary)`);
  return lintFile(path).rules.has("useFilenamingConvention");
};

test("canary · useFilenamingConvention can't enforce PascalCase incl. uppercase filenames", () => {
  const acceptsMyButton = !flagged("MyButton.vue");
  const acceptsVSC = !flagged("VSC.vue");
  const rejectsMybutton = flagged("mybutton.vue");
  const worksCorrectly = acceptsMyButton && acceptsVSC && rejectsMybutton;
  ok(
    !worksCorrectly,
    "Biome now enforces PascalCase component filenames correctly, including all-uppercase " +
      "acronyms (VSC.vue accepted, mybutton.vue flagged). The HACK in " +
      "layers/nuxt/overrides.jsonc disabling useFilenamingConvention for components is now " +
      "OBSOLETE: restore the commented PascalCase override and remove the HACK. " +
      `(observed: MyButton.vue ${acceptsMyButton ? "accepted" : "FLAGGED"}, ` +
      `VSC.vue ${acceptsVSC ? "accepted" : "FLAGGED"}, ` +
      `mybutton.vue ${rejectsMybutton ? "flagged" : "ACCEPTED"})`,
  );
});
