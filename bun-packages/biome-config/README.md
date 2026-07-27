# @wvffle/biome-config

Shared [Biome](https://biomejs.dev) configuration, published as layered configs.

## Primary layers (pick one)

| Layer  | Extend when…                       | Contains                                                            |
|--------|------------------------------------|--------------------------------------------------------------------|
| `base` | any TypeScript/JavaScript project  | formatter, assist, JS formatter, all framework-agnostic lint rules |
| `vue`  | a Vue project                      | everything in `base` **+** the `vue` domain and Vue-specific rules  |
| `nuxt` | a Nuxt project                     | everything in `vue` **+** the `.nuxt` ignore and Nuxt-path overrides |

These are **self-contained** — extend exactly one.

## Additive capability layers (opt-in, extend alongside a primary layer)

| Layer          | Adds                                                         | Cost when enabled                    |
|----------------|--------------------------------------------------------------|--------------------------------------|
| `types`        | type-aware rules (`noBaseToString`, `useAwaitThenable`, …)    | Biome Scanner + type inference       |
| `project-wide` | cross-file rules (`noUnresolvedImports`, `noImportCycles`, …) | Biome Scanner + project module graph |

These are **thin** (they do not include `base`) and their rules are **active** —
extending one turns those rules on. Enabling any of them spins up the Biome
Scanner over your whole project, so add them deliberately.

## Usage

```sh
bun add -d @wvffle/biome-config @biomejs/biome
```

> Uses [Bun](https://bun.sh). The package ships `trustedDependencies` so
> `bun install` lets Biome download its platform binary.

Extend one primary layer, optionally adding capability layers, in a single
`extends` array (a single array is fully merged):

```jsonc
{
  "$schema": "https://biomejs.dev/schemas/2.5.5/schema.json",
  "extends": [
    "@wvffle/biome-config/nuxt",
    "@wvffle/biome-config/types",
    "@wvffle/biome-config/project-wide"
  ],
  // repo-specific — not shipped in the package:
  "vcs": { "enabled": true, "clientKind": "git", "useIgnoreFile": true, "defaultBranch": "master" }
}
```

`vcs` lives in your own config: Biome has no lint rules gated on VCS (it only
governs file discovery), and `defaultBranch` is repo-specific.

## Style guide

A quick tour of the style each layer enforces — all snippets below are valid
(they pass the config and are shown as the formatter would print them).

**base** — formatter + framework-agnostic rules:

```ts
// Single quotes, no semicolons, 2-space indent, 120-col width, trailing commas.
const user = {
  name: 'Ada',
  roles: ['admin', 'editor'],
}

const greeting = `Hello, ${user.name}` // template literals over concatenation

function primaryRole(roles: readonly string[]): string | undefined {
  return roles.find((role) => role !== 'guest')
}

if (user.roles.length > 0) {
  primaryRole(user.roles)
}
```

**vue** — everything in `base`, plus the Vue domain:

```vue
<!-- TodoItem.vue — multi-word component name (useVueMultiWordComponentNames) -->
<script setup lang="ts">
const label = 'Save'
</script>

<template>
  <button>{{ label }}</button>
</template>
```

**nuxt** — everything in `vue`, plus overrides that make Nuxt's conventions
clean:

```ts
// nuxt.config.ts — default export and process.env are fine on *.config.ts
export default defineNuxtConfig({
  runtimeConfig: {
    apiBase: process.env.API_BASE,
  },
})

// app/stores/counter.ts — the trailing HMR block is allowed (useExportsLast off)
export const useCounter = defineStore('counter', () => ({ count: ref(0) }))
if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useCounter, import.meta.hot))
}
```

**types** (opt-in) — type-aware idioms; enabling adds the Biome scanner + type
inference:

```ts
const active = users.find((u) => u.isActive)     // useArrayFind
const sorted = [...scores].sort((a, b) => a - b)  // useArraySortCompare
const hasTag = tags.includes('urgent')            // useIncludes
await saveUser(user)                              // useAwaitThenable (a real promise)
const line = `total: ${count}`                    // noBaseToString (a primitive)
```

**project-wide** (opt-in) — cross-file guarantees; enabling adds the Biome
scanner + module graph:

```ts
import { saveUser } from './api/user' // resolves (noUnresolvedImports)
import { formatDate } from './date'   // not @deprecated (noDeprecatedImports)

// Enforced across the project: no import cycles (noImportCycles), dependencies
// under OSI/FSF-approved licenses (noUntrustedLicenses), and every CSS class
// used in markup is declared (noUndeclaredClasses / noUnusedClasses).
```

## Why self-contained bundles?

Biome resolves `extends` only **one level deep** — a config pulled in via
`extends` has its own `extends` silently ignored. A `nuxt → vue → base` chain
would drop almost everything. See:

- https://github.com/biomejs/biome/issues/1867
- https://github.com/biomejs/biome/discussions/8257

So each primary layer inlines what it needs. That inlining is generated.

## Development

Sources live in `layers/` (commented, with examples). The build
(`scripts/build.ts`) imports each JSONC layer natively via Bun, merges them, and
writes the comment-free `dist/` configs that `exports` points to:

```sh
bun run build
```

`dist/` is git-ignored and rebuilt automatically by the `bun test` preload and
on `prepublishOnly`, so the published package always contains it.

> Not `bun build`: Bun's bundler emits JavaScript modules, but Biome's `extends`
> only accepts `.json`/`.jsonc`, so the bundler can't produce these configs. The
> build runs on Bun directly (`bun scripts/build.ts`) and relies on Bun's native
> JSONC import.

## Testing

Real Biome runs on fixture files (Bun's built-in test runner). Each test lints a
fixture against the built `dist/` config and asserts which rules fire.

```sh
bun test
```

`bun test` is self-contained — a preload (`tests/setup.mjs`) rebuilds `dist/`
first, so it works from a fresh checkout.
