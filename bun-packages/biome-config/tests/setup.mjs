// Test preload: build the dist/ configs the tests lint against, so `bun test`
// works on its own without a separate build step.
import { build } from "../scripts/build.ts";
await build();
