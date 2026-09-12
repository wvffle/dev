{
  lib,
  fullCleanSource,
  mkTauriFrontend,
  crane,
  # Flake input, not a plain nixpkgs attribute — see flake.nix's own
  # comment on why the android target needs it (Rust std for the 4
  # Android ABIs, which plain nixpkgs doesn't ship).
  fenix,
  pkgs,
  cargo-tauri,
  pkg-config,
  wrapGAppsHook4,
  openssl,
  glib-networking,
  webkitgtk_4_1,
  pkgsCross,
  cargo-xwin,
  nsis,
  ninja,
  nasm,
  cmake,
  fetchurl,
  jdk21,
  gradle,
  cacert,
  mitm-cache,
  curl,
  python3Packages,
  ...
}: attrs @ {
  src,
  tauriRoot ? "src-tauri",
  # Interpolating "${src}/..." directly would addToStore the whole,
  # *unfiltered* src as a side effect (string interpolation of a path
  # always copies its entire root, not just the accessed subpath) - so
  # this goes through fullCleanSource first, which excludes .devenv (and
  # other cruft) during the copy instead of racing a live devenv process's
  # sqlite state files. Same reasoning applies to every other "${src}/..."
  # read below (lockFile, tauriCargoTomlPath, rootCargoTomlPath,
  # localPathDepsOf).
  tauriConf ? builtins.fromJSON (builtins.readFile "${fullCleanSource src {}}/${tauriRoot}/tauri.conf.json"),
  # Last-resort version fallback, used only when tauri.conf.json omits
  # version and it can't be resolved from ${tauriRoot}/Cargo.toml either
  # (directly, or via `version.workspace = true` pointing at the root
  # Cargo.toml's [workspace.package].version).
  version ? null,
  lockFile ?
    if builtins.pathExists "${fullCleanSource src {}}/Cargo.lock"
    then "${fullCleanSource src {}}/Cargo.lock"
    else "${fullCleanSource src {}}/${tauriRoot}/Cargo.lock",
  target ? "linux",
  # android-only: builds the release variant (optimized, minified) instead
  # of the debug one `androidBuildCmd` otherwise always passes `--debug`
  # for. linux/windows are already release-by-default regardless (`cargo
  # tauri build` with no `--debug` equivalent to opt out of), so this only
  # changes android's behavior.
  release ? false,
  # android-only, required when `release` is true: signs the release APK
  # instead of leaving it unsigned (which Gradle's own release build type
  # allows, but Android then refuses to `adb install` or accept as an
  # update over an existing install). `keystoreBase64` is the base64-
  # encoded content of a real `.jks` keystore (binary, hence base64 — see
  # `androidSigningSetup`'s own comment for why); `keyAlias`/`keyPassword`
  # match Tauri's own `keystore.properties` convention of one shared
  # password for both the store and the key inside it. Generate a
  # keystore with `keytool -genkey -keyalg RSA -keysize 2048 -validity
  # 10000 -alias <alias>` — see https://v2.tauri.app/distribute/sign/android/.
  androidSigning ? null,
  # android-only, required: the app's own per-project Gradle-dependency
  # lockfile (see `androidMitmCache`'s own comment for its format and how
  # to regenerate it) — a caller-supplied path, not a file living in this
  # shared repo, so that a second android-targeting app doesn't collide
  # with this one's on the exact same `./android-deps.json` path. No
  # sensible shared default exists; the `throw` only actually fires if an
  # `isAndroid` caller omits it (Nix's own laziness means a non-android
  # caller never forces this thunk at all).
  androidDepsFile ?
    throw "mkTauriApp: target \"android\" needs androidDepsFile set to this app's own deps.json lockfile (e.g. apps/kiosk/android-deps.json, not a shared one in this repo)",
  updater ? {enable = false;},
  nsisTauriUtils ? {
    version = "0.5.3";
    hash = "sha256-W6FDtdtKh9MtbngC4DMzCq5Wy86r4NHjukGUg4WtRwk=";
  },
  postInstall ? "",
  nativeBuildInputs ? [],
  buildInputs ? [],
  env ? {},
  # Forwarded to mkTauriFrontend to scope its source in a monorepo; see
  # its docs for defaults/semantics.
  frontendRoot ? builtins.dirOf tauriRoot,
  extraFrontendSrcPaths ? [],
  # Extra paths (relative to src) to seed the Rust dependency-closure walk
  # with, alongside tauriRoot - for anything rustClosure's Cargo.toml-based
  # detection can't see, e.g. a crate's `include_bytes!`/`include_str!`
  # pulling in a plain asset directory that isn't a path dependency at all.
  # A crate dir here also gets its own local path deps pulled in normally;
  # a plain asset dir just gets included as-is (it has no Cargo.toml, so
  # nothing further is discovered from it).
  extraSrcPaths ? [],
  # android-only knobs — versions pinned here become part of what
  # `gen/android`'s own checked-in `app/build.gradle.kts` (compileSdk/
  # targetSdk, written by `cargo tauri android init`) expects to find
  # installed; keep them in sync if that file's numbers ever change.
  android ? {},
  ...
}: let
  isWindows = target == "windows";
  isLinux = target == "linux";
  isAndroid = target == "android";

  androidMinSdk = android.minSdk or 24;
  androidPlatformVersion = android.platformVersion or "36";
  # AGP pulls in a build-tools version other than compileSdk's own to
  # satisfy specific tasks (observed: :app:compileUniversalDebugJavaWithJavac
  # wants 35.0.0 even at compileSdk 36) and, finding it missing, tries to
  # `sdkmanager --install` it into $ANDROID_HOME at build time — which is
  # always read-only here (a Nix store path) regardless of target, so
  # that install can only ever fail. Provisioning every version AGP has
  # been observed to reach for up front is what avoids it ever trying.
  androidBuildToolsVersions = android.buildToolsVersions or ["35.0.0" "36.0.0"];
  androidNdkVersion = android.ndkVersion or "29.0.14206865";

  isNonEmptyVersion = v: v != null && v != "" && v != true;

  # See the comment on the `tauriConf` parameter default above: every read
  # below goes through this filtered copy instead of interpolating `src`
  # directly, to avoid addToStore-ing the whole unfiltered project (and
  # racing live tooling like devenv's sqlite state files in .devenv).
  cleanSrc = fullCleanSource src {};

  # Tauri itself falls back to the package Cargo.toml's version when
  # tauri.conf.json omits it, and that version may in turn be inherited
  # from the workspace via `version.workspace = true` (parsed as the
  # table { workspace = true; }). Both Cargo.toml reads stay inside `src`
  # (no walking above it, which doesn't work: `src` is a Nix store path
  # containing only the given subtree, so a parent directory outside it
  # isn't the real workspace root even if one exists on disk).
  tauriCargoTomlPath = "${cleanSrc}/${tauriRoot}/Cargo.toml";
  tauriCargoToml =
    if builtins.pathExists tauriCargoTomlPath
    then builtins.fromTOML (builtins.readFile tauriCargoTomlPath)
    else {};
  cargoPkgVersion = tauriCargoToml.package.version or null;
  cargoPkgVersionIsWorkspaceInherit =
    builtins.isAttrs cargoPkgVersion && (cargoPkgVersion.workspace or false) == true;
  cargoResolvedVersion =
    if cargoPkgVersionIsWorkspaceInherit
    then rootCargoToml.workspace.package.version or null
    else cargoPkgVersion;

  # Prefer tauriConf.version, then the (possibly workspace-inherited) Cargo
  # version, then the explicit `version` argument as a last resort.
  resolvedVersion =
    if tauriConf ? version && isNonEmptyVersion tauriConf.version
    then toString tauriConf.version
    else if isNonEmptyVersion cargoResolvedVersion
    then toString cargoResolvedVersion
    else if isNonEmptyVersion version
    then toString version
    else throw "mkTauriApp: could not resolve a version from tauri.conf.json, ${tauriRoot}/Cargo.toml (including workspace.package.version), or an explicit `version` argument";

  pname = "${tauriConf.productName}-${target}";

  releaseType =
    if isWindows
    then "x86_64-pc-windows-gnu/release"
    else if isAndroid
    then "android"
    else "release";

  # ---- Android SDK/NDK/Rust-std ----
  #
  # `androidenv.composeAndroidPackages` lives behind a license-acceptance
  # gate (pkgs.androidenv's own `license.nix`, keyed off
  # `config.android_sdk.accept_license`) — re-importing nixpkgs from
  # `pkgs.path` with that one config bit flipped keeps the acceptance
  # scoped to just this android-only package set, rather than forcing
  # every consumer of `mkTauriApp` to carry that config flag on their own
  # top-level `pkgs` just to get a working `target = "windows"`/`"linux"`
  # build (which never touch androidenv at all).
  androidLicensedPkgs = import pkgs.path {
    inherit (pkgs) system;
    config = (pkgs.config or {}) // {android_sdk.accept_license = true;};
  };

  androidSdk = androidLicensedPkgs.androidenv.composeAndroidPackages {
    includeNDK = true;
    ndkVersions = [androidNdkVersion];
    platformVersions = [androidPlatformVersion];
    buildToolsVersions = androidBuildToolsVersions;
  };
  androidSdkRoot = "${androidSdk.androidsdk}/libexec/android-sdk";
  androidNdkRoot = "${androidSdkRoot}/ndk/${androidNdkVersion}";
  androidNdkBin = "${androidNdkRoot}/toolchains/llvm/prebuilt/linux-x86_64/bin";

  # One NDK clang wrapper (baking in `androidMinSdk`) per Rust target
  # triple — cargo's own `CARGO_TARGET_<TRIPLE>_LINKER` (and the matching
  # CC/CXX/AR a build-dependency's `cc` crate needs) is how it's told to
  # use the NDK's cross linker/compiler instead of the host's. Tauri's own
  # `android-studio-script` sets these dynamically at invocation time
  # (never persisted to a `.cargo/config.toml` in `gen/android` — confirmed
  # empirically, see this file's own git history/commit message) — set the
  # same way here, just once, for cargo AND every recursive `cargo tauri
  # android android-studio-script` re-invocation gradle's own `rustBuild*`
  # tasks make (see `tauriConfigPatch`'s own comment for why those
  # recursive calls happen at all) to inherit unchanged.
  androidRustTargets = [
    {
      triple = "aarch64-linux-android";
      envTarget = "AARCH64_LINUX_ANDROID";
      clangPrefix = "aarch64-linux-android";
    }
    {
      triple = "armv7-linux-androideabi";
      envTarget = "ARMV7_LINUX_ANDROIDEABI";
      clangPrefix = "armv7a-linux-androideabi";
    }
    {
      triple = "i686-linux-android";
      envTarget = "I686_LINUX_ANDROID";
      clangPrefix = "i686-linux-android";
    }
    {
      triple = "x86_64-linux-android";
      envTarget = "X86_64_LINUX_ANDROID";
      clangPrefix = "x86_64-linux-android";
    }
  ];
  androidCargoEnv = lib.listToAttrs (lib.concatMap (t: let
    clang = "${androidNdkBin}/${t.clangPrefix}${toString androidMinSdk}-clang";
    clangxx = "${androidNdkBin}/${t.clangPrefix}${toString androidMinSdk}-clang++";
    triple_ = lib.replaceStrings ["-"] ["_"] t.triple;
  in [
    {
      name = "CARGO_TARGET_${t.envTarget}_LINKER";
      value = clang;
    }
    {
      name = "CC_${triple_}";
      value = clang;
    }
    {
      name = "CXX_${triple_}";
      value = clangxx;
    }
    {
      name = "AR_${triple_}";
      value = "${androidNdkBin}/llvm-ar";
    }
  ]) androidRustTargets);

  # Plain nixpkgs rustc only ever ships std for its own build platform —
  # fenix is what supplies std for the 4 Android ABIs on top of the same
  # stable channel, as ordinary fetchurl derivations (Rust's own prebuilt
  # release components), so `craneLib.overrideToolchain` below still gets a
  # ordinary derivation-backed toolchain crane already knows how to drive.
  androidRustToolchain = let
    fenixPkgs = fenix.packages.${pkgs.system};
  in
    fenixPkgs.combine ([fenixPkgs.stable.toolchain]
      ++ map (t: fenixPkgs.targets.${t.triple}.stable.rust-std) androidRustTargets);

  craneLib =
    if isWindows
    then crane.mkLib pkgsCross.mingwW64
    else if isAndroid
    then (crane.mkLib pkgs).overrideToolchain androidRustToolchain
    else crane.mkLib pkgs;

  # ---- Rust source ----

  rootCargoTomlPath = "${cleanSrc}/Cargo.toml";
  rootCargoToml =
    if builtins.pathExists rootCargoTomlPath
    then builtins.fromTOML (builtins.readFile rootCargoTomlPath)
    else {};

  relOf = path: lib.removePrefix (toString src + "/") (toString path);
  isUnderCrateDir = rel: crateDir: rel == crateDir || lib.hasPrefix "${crateDir}/" rel;

  splitPath = p: lib.filter (s: s != "" && s != ".") (lib.splitString "/" p);
  joinPath = parts: lib.concatStringsSep "/" parts;

  # Cargo's `[workspace] members` entries may be globs (each path segment
  # matched independently via the `glob` crate, e.g. "crates/*") - treating
  # them as literal paths (as opposed to expanding them here) leaves a
  # bogus "crates/*" entry that breaks Cargo's own workspace resolution
  # later, since no such literal directory exists. This doesn't implement
  # `[workspace] exclude`.
  escapeRegexChar = c:
    if builtins.elem c ["." "+" "?" "(" ")" "[" "]" "{" "}" "^" "$" "|" "\\"]
    then "\\${c}"
    else c;
  segmentToRegex = seg: lib.concatStrings (map (c: if c == "*" then ".*" else escapeRegexChar c) (lib.stringToCharacters seg));
  expandMemberGlob = pattern: let
    go = baseDir: segs:
      if segs == []
      then [baseDir]
      else let
        seg = builtins.head segs;
        rest = builtins.tail segs;
        joined = if baseDir == "" then seg else "${baseDir}/${seg}";
      in
        if !(lib.hasInfix "*" seg)
        then
          if builtins.pathExists "${cleanSrc}/${joined}"
          then go joined rest
          else []
        else let
          dirToList =
            if baseDir == ""
            then cleanSrc
            else "${cleanSrc}/${baseDir}";
          entries =
            if builtins.pathExists dirToList
            then builtins.readDir dirToList
            else {};
          regex = segmentToRegex seg;
          matches = lib.filter (name: entries.${name} == "directory" && builtins.match regex name != null) (builtins.attrNames entries);
        in
          lib.concatMap (name: go (if baseDir == "" then name else "${baseDir}/${name}") rest) matches;
  in
    go "" (splitPath pattern);

  workspaceMembers =
    if builtins.pathExists rootCargoTomlPath
    then lib.concatMap expandMemberGlob (rootCargoToml.workspace.members or [])
    else [];

  # Resolve a Cargo.toml `path = "..."` value written in `fromDir` (a crate
  # dir relative to src) into a path relative to src, collapsing ".."
  # segments (string paths can't rely on Nix's own path normalization).
  resolveRelPath = fromDir: rel: let
    base = splitPath fromDir;
    parts = splitPath rel;
    go = acc: remaining:
      if remaining == []
      then acc
      else let
        p = builtins.head remaining;
        rest = builtins.tail remaining;
      in
        if p == ".."
        then go (if acc == [] then acc else lib.init acc) rest
        else go (acc ++ [p]) rest;
  in
    joinPath (go base parts);

  workspaceDependencies = rootCargoToml.workspace.dependencies or {};

  depTablesOf = cargoToml: let
    targetTables = builtins.attrValues (cargoToml.target or {});
    fromTarget =
      lib.concatMap (t: [
        (t.dependencies or {})
        (t.dev-dependencies or {})
        (t.build-dependencies or {})
      ])
      targetTables;
  in
    [
      (cargoToml.dependencies or {})
      (cargoToml.dev-dependencies or {})
      (cargoToml.build-dependencies or {})
    ]
    ++ fromTarget;

  # Local path dependencies declared by the crate at `crateDir`. A direct
  # `{ path = ... }` spec is relative to crateDir; a `{ workspace = true }`
  # spec instead points at [workspace.dependencies] in the root Cargo.toml,
  # whose `path` is relative to the workspace root - the two need
  # different bases when resolving ".." segments.
  localPathDepsOf = crateDir: let
    cargoTomlPath = "${cleanSrc}/${crateDir}/Cargo.toml";
    cargoToml =
      if builtins.pathExists cargoTomlPath
      then builtins.fromTOML (builtins.readFile cargoTomlPath)
      else {};
    tables = depTablesOf cargoToml;

    directPathsIn = table:
      lib.filter (p: p != null) (map (
        spec:
          if builtins.isAttrs spec && spec ? path
          then resolveRelPath crateDir spec.path
          else null
      ) (builtins.attrValues table));

    workspaceInheritedPathsIn = table:
      lib.filter (p: p != null) (map (
        name: let
          spec = table.${name};
          wsSpec = workspaceDependencies.${name} or {};
        in
          if builtins.isAttrs spec && (spec.workspace or false) == true && wsSpec ? path
          then resolveRelPath "." wsSpec.path
          else null
      ) (builtins.attrNames table));
  in
    lib.concatMap directPathsIn tables ++ lib.concatMap workspaceInheritedPathsIn tables;

  # Full Rust source is only needed for tauriRoot and the crates it
  # actually (transitively) depends on via a local path - not every crate
  # in a large monorepo-wide workspace. Other workspace members still need
  # their Cargo.toml present (Cargo eagerly parses every listed member's
  # manifest to resolve the workspace/lockfile even if it isn't built),
  # just not their full source.
  rustClosure = let
    step = acc: let
      discovered = lib.unique (lib.concatMap localPathDepsOf acc);
      combined = lib.unique (acc ++ discovered);
    in
      if combined == acc
      then acc
      else step combined;
  in
    step ([tauriRoot] ++ extraSrcPaths);

  manifestOnlyCrateDirs = lib.subtractLists rustClosure workspaceMembers;
  manifestOnlyPaths = map (dir: "${dir}/Cargo.toml") manifestOnlyCrateDirs;

  # Ancestor directories of every kept path must also pass the filter -
  # fullCleanSource/cleanSourceWith won't recurse into a directory whose
  # own filter call returns false, so e.g. "crates" and "crates/unused-lib"
  # must still be allowed purely for traversal even though only
  # crates/unused-lib/Cargo.toml (not its full source) is actually kept.
  allowRootPaths = ["Cargo.toml" "Cargo.lock"] ++ rustClosure ++ manifestOnlyPaths;
  isAncestorOfAllowRoot = rel: lib.any (t: lib.hasPrefix "${rel}/" t) allowRootPaths;

  isRustSrcPath = path: type: let
    rel = relOf path;
  in
    rel == "Cargo.toml"
    || rel == "Cargo.lock"
    || lib.any (isUnderCrateDir rel) rustClosure
    || lib.elem rel manifestOnlyPaths
    || isAncestorOfAllowRoot rel;

  # Whitelist: allow claims everything under a rust crate dir (bypassing
  # the default filter's *.o/*.so strip, needed for vendored prebuilt
  # libs like elzabdr.so); deny is the exact negation, making this an
  # exclusive whitelist rather than "default plus exceptions".
  filteredRustSrc = fullCleanSource src {
    allow = [isRustSrcPath];
    deny = [(path: type: !(isRustSrcPath path type))];
  };

  # A manifest-only crate's Cargo.toml is present (Cargo needs it to
  # resolve the workspace) but it has no source, and Cargo hard-errors
  # parsing a manifest with zero targets ("no targets specified ... either
  # src/lib.rs, src/main.rs, a [lib] section, or [[bin]] section must be
  # present"). Since nothing in rustClosure depends on these crates, they
  # never actually get compiled - stub content that merely satisfies target
  # discovery is enough (same technique cargo-chef uses for Docker layer
  # caching). This doesn't handle a manifest-only crate with an *explicit*
  # non-default target path (e.g. `[lib] path = "src/custom.rs"`); that
  # would need a matching stub at that exact path instead.
  rustSrc =
    if manifestOnlyCrateDirs == []
    then filteredRustSrc
    else
      pkgs.runCommand "rust-src-with-stubs" {} ''
        cp -r ${filteredRustSrc} $out
        chmod -R u+w $out
        ${lib.concatMapStringsSep "\n" (dir: ''
            mkdir -p "$out/${dir}/src"
            : > "$out/${dir}/src/lib.rs"
            printf 'fn main() {}\n' > "$out/${dir}/src/main.rs"
          '')
          manifestOnlyCrateDirs}
      '';

  # Frontend/Rust source splitting now lives inside mkTauriFrontend
  # itself, since it already reads tauriConf/tauriRoot.
  frontend =
    attrs.frontend or (mkTauriFrontend {
      inherit src tauriRoot frontendRoot tauriConf;
      extraSrcPaths = extraFrontendSrcPaths;
      version = resolvedVersion;
    });

  # android-only, historical note: upstream's generated `gen/android`
  # Gradle project shells back out to `pnpm tauri android android-studio-
  # script` per ABI (its bundled `buildSrc` Gradle plugin's `BuildTask.kt`
  # hardcodes the `pnpm` executable) — this repo's own copy of that
  # generated file is patched to invoke `cargo-tauri` directly instead (its
  # own comment explains why: confirmed via `cargo-tauri android android-
  # studio-script --help` that it's the exact same underlying logic the
  # npm-wrapped CLI re-execs anyway). With that patch in place, android no
  # longer needs any of its own JS tooling at build time — same as linux/
  # windows, `frontend` above (already built) is all either target needs.
  tauriConfigPatch = builtins.toJSON (lib.foldl' lib.recursiveUpdate {} [
    {
      build = {
        frontendDist = "${frontend}";
        beforeBuildCommand = "";
      };
    }
    (lib.optionalAttrs updater.enable {
      plugins.updater.endpoints = updater.endpoints;
      plugins.updater.pubkey = updater.publicKey;
      bundle.createUpdaterArtifacts = true;
    })
    (lib.optionalAttrs isWindows {
      bundle.active = true;
      bundle.targets = "nsis";
    })
  ]);

  nsis-tauri-utils-dll = fetchurl {
    url = "https://github.com/tauri-apps/nsis-tauri-utils/releases/download/nsis_tauri_utils-v${nsisTauriUtils.version}/nsis_tauri_utils.dll";
    inherit (nsisTauriUtils) hash;
  };

  platformNativeInputs =
    (
      if isWindows
      then [cargo-tauri pkg-config cargo-xwin nasm ninja cmake nsis]
      else if isAndroid
      # Plain `cargo-tauri`, not `.hook`: `androidBuildCmd` below invokes it
      # directly (matching how the `isWindows` branch above also uses the
      # plain package, for the same reason — `buildCmd` there is explicit
      # too), rather than relying on a hook-injected default build phase.
      # This repo's own `gen/android/buildSrc/.../BuildTask.kt` is patched
      # to invoke this same `cargo-tauri` binary too (see `tauriConfigPatch`'s
      # own comment) — no `pnpm`/`nodejs` needed anywhere in this build
      # anymore, JS tooling is `frontend`'s own concern (already built, same
      # as linux/windows), not this final derivation's. `androidSdk.androidsdk`
      # alone provides every SDK binary this needs (sdkmanager/adb/build-
      # tools) — see its own comment above.
      # `gradle` (the top-level nixpkgs attribute, not `gradle-unwrapped`)
      # already bundles the `mitm-cache` binary itself and its setup hook
      # via its own `symlinkJoin` — see gradle/default.nix's `wrapGradle` —
      # so it doesn't need listing separately here too.
      then [jdk21 gradle cargo-tauri androidSdk.androidsdk]
      else [cargo-tauri.hook pkg-config wrapGAppsHook4]
    )
    ++ nativeBuildInputs;

  platformBuildInputs =
    (
      if isWindows
      then [openssl]
      else if isAndroid
      # Android's WebView is the OS's own, not webkitgtk_4_1 (Linux-only);
      # tauri-plugin-http/reqwest use rustls here too, so no openssl either.
      then []
      else [openssl webkitgtk_4_1 glib-networking]
    )
    ++ buildInputs;

  commonArgs =
    {
      inherit pname;
      version = resolvedVersion;
      # Pure Rust source, same as every other target — no JS tooling
      # involved in this derivation at all (see `tauriConfigPatch`'s own
      # comment on why android needs none either, unlike an earlier version
      # of this file).
      src = rustSrc;
      cargoLock = lockFile;
      strictDeps = true;
      doCheck = false;
      nativeBuildInputs = platformNativeInputs;
      buildInputs = platformBuildInputs;
      NIX_CFLAGS_COMPILE = lib.optionalString isWindows "-Wno-error=stringop-overflow";
      # Scopes crane's own cargo invocations (buildDepsOnly's `cargo check`
      # in particular) to just the tauri package, instead of the whole
      # workspace's default members - otherwise unrelated sibling crates
      # (other apps, test-only crates with their own heavy/incompatible
      # dependencies) get needlessly resolved and built too. `cargo tauri
      # build` below already targets the app on its own and ignores this.
      cargoExtraArgs = "-p ${tauriCargoToml.package.name}";
    }
    // env
    // lib.optionalAttrs updater.enable {
      TAURI_SIGNING_PRIVATE_KEY = updater.privateKey;
      TAURI_SIGNING_PRIVATE_KEY_PASSWORD = updater.privateKeyPassword;
    }
    // lib.optionalAttrs isAndroid androidEnv
    // lib.optionalAttrs (isAndroid && release && androidSigning != null) {
      ANDROID_SIGNING_KEYSTORE_BASE64 = androidSigning.keystoreBase64;
      ANDROID_SIGNING_KEY_ALIAS = androidSigning.keyAlias;
      ANDROID_SIGNING_KEY_PASSWORD = androidSigning.keyPassword;
    };

  androidEnv =
    {
      ANDROID_HOME = androidSdkRoot;
      ANDROID_SDK_ROOT = androidSdkRoot;
      NDK_HOME = androidNdkRoot;
      JAVA_HOME = jdk21.home;
    }
    // androidCargoEnv;

  commonPreBuild = ''
    export CARGO_BUILD_JOBS="$NIX_BUILD_CORES"
  '';

  windowsPreBuild =
    commonPreBuild
    + ''
      export HOME=$(mktemp -d)
      mkdir -p $HOME/.cache/tauri/NSIS/Plugins/x86-unicode/additional
      cp ${nsis-tauri-utils-dll} $HOME/.cache/tauri/NSIS/Plugins/x86-unicode/additional/nsis_tauri_utils.dll
      export CARGO_PROFILE_RELEASE_STRIP=false
    '';

  # A writable $HOME (gradle/cargo both want to write config/caches under
  # it) plus `cd`ing into the frontend root, matching where a real `cargo
  # tauri android build` would run from by hand — everything past this
  # point (`androidBuildCmd`, and the recursive `cargo tauri ...` calls
  # gradle's own `rustBuild*` tasks make) assumes that CWD.
  androidPreBuild =
    assert lib.assertMsg (!release || androidSigning != null)
    "mkTauriApp: target \"android\" with release = true needs androidSigning set (a real signing config is required to package a release APK — unlike debug, there's no automatic fallback keystore).";
    commonPreBuild
    + ''
      export HOME=$(mktemp -d)
      # crane's own configureCargoVendoredDepsHook (already run by this
      # point, during configurePhase) points cargo's crates-io source
      # replacement straight at the vendored deps' Nix store path — fine
      # for every ordinary build script (cargo gives those a real writable
      # scratch dir via OUT_DIR), but tauri-plugin's own build.rs writes
      # into its *own* `CARGO_MANIFEST_DIR` instead when cross-compiling
      # for android/ios specifically (copying its bundled `tauri-api` JS
      # next to a `.tauri` dir it creates there) — confirmed by reading
      # tauri-plugin-2.6.3/src/build/mobile.rs directly, and only surfaces
      # here because linux/windows never hit that `cfg(mobile)` branch.
      # /nix/store itself is mounted read-only, so no chmod can fix this in
      # place — copying the whole vendored tree out and repointing cargo's
      # own config at that copy is the only way around it.
      # A sibling of the already-unpacked source (which `chmod` just proved
      # writable) rather than under `$HOME`: on at least one remote builder
      # this build ran against, a freshly `mktemp -d`'d `$HOME` landed on a
      # mount where `chmod` itself failed outright ("Operation not
      # permitted") even on a directory this same build had just created —
      # confirmed empirically, not something narrower to `chmod -R` on a
      # copy specifically.
      vendor_dir=$(sed -n 's/^directory = "\(.*\)"$/\1/p' "$CARGO_HOME/config.toml" | tail -1)
      if [ -n "$vendor_dir" ]; then
        writable_vendor_dir="$PWD/.cargo-vendor-writable"
        # `-L`/dereference, not a plain `cp -r`: crane's own vendor
        # directory is built entirely out of `ln -s` entries, one per
        # crate, each pointing at that crate's own Nix store output (see
        # crane's vendorMultipleCargoDeps.nix) — a plain `cp -r` copies
        # those symlinks *as symlinks*, so `CARGO_MANIFEST_DIR` for any
        # vendored crate still resolves straight through to a read-only
        # /nix/store path either way (confirmed empirically: `chmod -R u+w`
        # on the naive copy failed outright, "Operation not permitted",
        # because it was chasing the symlink into /nix/store, which is
        # mounted read-only at the filesystem level — no permission bits
        # can fix that). `-L` copies each symlink's real target content
        # instead, so every crate becomes a genuine, independent, writable
        # copy.
        cp -rL "$vendor_dir" "$writable_vendor_dir"
        chmod -R u+w "$writable_vendor_dir"
        sed -i "s|directory = \"$vendor_dir\"|directory = \"$writable_vendor_dir\"|" "$CARGO_HOME/config.toml"
      fi
      # The tauri CLI always execs `gen/android/gradlew` directly (its own
      # Rust code hardcodes this, confirmed empirically — not something a
      # `gradle` already on $PATH gets substituted for), and the real
      # gradlew is a wrapper script whose entire purpose is downloading
      # (over the network, using gradle-wrapper.properties' own pinned
      # version/URL) whatever gradle version isn't already cached under
      # $GRADLE_USER_HOME in gradle's own hashed-by-URL layout — replicating
      # that layout just to make gradlew think it's already cached is far
      # more fragile than just not running the real gradlew at all: replace
      # it with a one-line passthrough to the `gradle` this derivation
      # already provides via nativeBuildInputs. Its shebang (`#!/usr/bin/env
      # sh`, both the original file's and this replacement's) needs
      # patchShebangs regardless — the Nix build sandbox has no FHS paths at
      # all (no /usr/bin/env), and the tauri CLI execs this script directly,
      # not through a shell that could resolve `env` via $PATH first.
      cat > ${tauriRoot}/gen/android/gradlew <<'GRADLEW_EOF'
#!/usr/bin/env sh
exec gradle "$@"
GRADLEW_EOF
      chmod +x ${tauriRoot}/gen/android/gradlew
      patchShebangs ${tauriRoot}/gen/android/gradlew
      # AGP's default aapt2 comes from its own Maven-resolved artifact
      # (`com.android.tools.build:aapt2`, unpacked fresh into Gradle's own
      # dependency-transform cache) — a prebuilt dynamically-linked Linux
      # binary expecting a standard FHS `/lib64/ld-linux-x86-64.so.2`,
      # which the Nix build sandbox doesn't have (confirmed empirically:
      # "AAPT2 ... Daemon startup failed" with no further detail, the
      # classic symptom of an unpatched ELF interpreter). The android SDK's
      # own build-tools package (already a nativeBuildInput here) already
      # runs every binary in it through autoPatchelf — see nixpkgs'
      # androidenv build-tools.nix — so pointing AGP at that copy instead,
      # via its own documented override property, sidesteps needing to
      # patchelf anything ourselves.
      # A leading newline, not a bare `echo >>`: the committed
      # gradle.properties has no trailing newline of its own, so a bare
      # append landed directly on the end of its last line and got parsed
      # as one bogus combined property (confirmed empirically).
      printf '\nandroid.aapt2FromMavenOverride=%s/build-tools/%s/aapt2\n' \
        "${androidSdkRoot}" "${lib.last androidBuildToolsVersions}" \
        >> ${tauriRoot}/gen/android/gradle.properties
    ''
    + lib.optionalString (release && androidSigning != null) ''
      # `gen/android/app/build.gradle.kts`'s own `signingConfigs.create
      # ("release")` block (see this repo's own patch, and https://
      # v2.tauri.app/distribute/sign/android/ for the upstream convention
      # it follows) reads exactly this file — `rootProject.file(...)`
      # resolves relative to `gen/android` itself, so an absolute path
      # sidesteps needing to reason about Gradle's own CWD at read time.
      # `$ANDROID_SIGNING_*` come from `commonArgs`' own env (real secret
      # values, kept out of this *file*'s source — only reaching the
      # store via the derivation's env, same as `TAURI_SIGNING_PRIVATE_KEY`
      # above already does).
      keystore_path="$PWD/${tauriRoot}/gen/android/upload-keystore.jks"
      base64 -d <<< "$ANDROID_SIGNING_KEYSTORE_BASE64" > "$keystore_path"
      cat > ${tauriRoot}/gen/android/keystore.properties <<KEYSTORE_PROPERTIES_EOF
      password=$ANDROID_SIGNING_KEY_PASSWORD
      keyAlias=$ANDROID_SIGNING_KEY_ALIAS
      storeFile=$keystore_path
      KEYSTORE_PROPERTIES_EOF
    ''
    + ''
      cd ${frontendRoot}
    '';

  # `cargo tauri android build`, matching the `gen/android/buildSrc`
  # patch's own invocation style (see `tauriConfigPatch`'s comment) — no
  # `pnpm`/JS tooling anywhere in this build anymore, top-level or
  # recursive. `--debug` opts *out* of the (default) release build —
  # dropped when `release` is set, so Gradle picks up `androidSigningSetup`'s
  # own signing config for the `release` build type instead of leaving it
  # unsigned. `--apk` (not the default AAB) is what Google Play doesn't
  # require and is directly `adb install`-able for testing.
  androidBuildCmd =
    "cargo tauri android build --apk"
    + lib.optionalString (!release) " --debug"
    + " --config '${tauriConfigPatch}'";

  # `androidPreBuild`'s own final `cd ${frontendRoot}` (its own comment
  # explains why: matching where a real `cargo tauri android build` runs
  # from by hand) means CWD is already `frontendRoot` by the time this
  # runs, in `installPhase` — `tauriRoot` itself is relative to the
  # original build root, not `frontendRoot`, so it needs `frontendRoot`'s
  # own prefix stripped first or this doubles up (`apps/kiosk/apps/kiosk/
  # tauri/gen/...`) and never finds the APK — confirmed empirically, the
  # first time this build ever got far enough to reach `installPhase` with
  # a real one built.
  androidInstallCmd = ''
    mkdir -p $out
    apk=$(find "${lib.removePrefix "${frontendRoot}/" tauriRoot}/gen/android/app/build/outputs/apk" -name '*.apk' -print -quit)
    if [ -z "$apk" ]; then
      echo "androidInstallCmd: no .apk found under gen/android/app/build/outputs/apk" >&2
      exit 1
    fi
    cp -v "$apk" $out/
  '';

  # Cargo's own deps are already handled hermetically by crane (below) the
  # same way as every other target — `cargoVendorDir`, derived from
  # `cargoLock`, needs no network and no FOD of its own. Gradle has no such
  # nix-native story built in, but nixpkgs itself solves exactly this via
  # `mitm-cache`: each dependency artifact is fetched individually (a plain
  # `fetchurl`, hashed on its own), and at real build time Gradle talks to a
  # local replay proxy over what it believes is a normal network connection
  # — genuine online-looking resolution, not `--offline` against a raw copy
  # of some prior run's `~/.gradle/caches`. That distinction is exactly what
  # an earlier version of this file got wrong: hashing the *whole* Gradle
  # cache directory as one recursive-NAR FOD, which turned out to be
  # non-deterministic (3 of Gradle's own internal freshness-index files
  # changed byte-for-byte between otherwise-identical populations), and —
  # once those 3 files were stripped to fix that — *also* broke offline
  # resolution of `gen/android/buildSrc`'s own `org.gradle.kotlin.kotlin-dsl`
  # plugin, which turned out to depend on those same files to *locate*
  # cached plugin artifacts, not just to freshness-check them. Individually-
  # hashed per-artifact fetches have no such freshness-index concept to get
  # wrong in the first place.
  #
  # `androidDepsFile` is a single per-app JSON file shaped:
  #   { "androidMitmRecordHash": {"debug": "sha256-...", "release": "sha256-..."},
  #     "dependencies": {"<url>": {"hash": "sha256-..."}, ...} }
  # `dependencies` is mitm-cache's own `fetch.nix` format directly (not nixpkgs'
  # `gradle.fetchDeps`'s *compressed* tree-shaped format, which needs a real
  # nixpkgs `pkg.meta.position` to resolve relative paths and buys nothing
  # here beyond a smaller diff, not something a private, single-consumer
  # lockfile needs) — covers *both* the debug and release dependency graphs
  # in one map (AGP resolves `debugRuntimeClasspath`/`releaseRuntimeClasspath`
  # separately, so recording only one build type misses the other's own
  # extra entries — confirmed empirically, a release-only build failed at
  # `generateReleaseLintModel` unable to resolve artifacts a debug-only
  # recording never captured). `androidMitmRecordHash` is this same file's
  # own record of `androidMitmRecord`'s expected output hash *per variant*
  # (see `outputHash`'s own comment below for why it's per-variant, not one
  # shared value) — kept alongside `dependencies` instead of in outputs.nix so
  # `update-android-deps <app>` can read *and* write the whole regenerate-
  # and-pin cycle in one place, no separate Nix edit ever required.
  # Regenerate/extend `dependencies` by building `androidMitmRecord` (same `devenv
  # build`/nixbuild.net pipeline as everything else — it's a real FOD, so it
  # gets network regardless of sandboxing) with the relevant `release` value
  # and merging its `$out/deps.json` into `dependencies`, whenever this app's
  # Gradle-side dependencies change (AGP/Kotlin/AndroidX version bumps,
  # mostly) or a not-yet-covered build type is built for the first time.
  androidDepsData = lib.importJSON androidDepsFile;

  androidMitmCache = mitm-cache.fetch {
    name = "${pname}-android-deps";
    data = androidDepsData.dependencies;
  };

  # The recording half of the update dance described above. A genuine FOD,
  # same reasoning as every other network-needing step in this file (see
  # `outputHash`'s own comment on the update dance) — *not* one hash over
  # the whole Gradle cache tree the way the old `androidGradleDeps` was
  # (that's exactly what turned out non-deterministic), but one hash over
  # this derivation's own small `deps.json`, whose *content* (real
  # cryptographic hashes of fetched artifacts, `jq -S`-sorted below for
  # canonical key order) is what mitm-cache is specifically designed to
  # make stable — the whole reason this file moved to mitm-cache in the
  # first place.
  androidMitmRecord = craneLib.mkCargoDerivation (commonArgs
    // {
      pname = "${pname}-android-mitm-record";
      cargoArtifacts = null;
      dontFixup = true;
      nativeBuildInputs = platformNativeInputs ++ [curl pkgs.jq python3Packages.ephemeral-port-reserve];
      buildPhaseCargoCommand = androidBuildCmd;
      preBuild =
        androidPreBuild
        + ''
          export GRADLE_USER_HOME=$HOME/.gradle
          mitmRecordDir=$(mktemp -d)
          pushd "$mitmRecordDir" >/dev/null
          openssl genrsa -out ca.key 2048
          openssl req -x509 -new -nodes -key ca.key -sha256 -days 1 -out ca.cer \
            -subj "/C=AL/ST=a/L=a/O=a/OU=a/CN=example.org"
          export MITM_CACHE_HOST=127.0.0.1
          export MITM_CACHE_PORT=$(ephemeral-port-reserve "$MITM_CACHE_HOST")
          export MITM_CACHE_ADDRESS="$MITM_CACHE_HOST:$MITM_CACHE_PORT"
          # mitm-cache's own outbound TLS client (talking to the *real*
          # upstream servers, to actually fetch content in record mode)
          # needs a real, valid CA bundle from the moment its process
          # launches below — a bare Nix sandbox has no system one at all
          # (confirmed empirically: without this, mitm-cache panics
          # immediately with "could not load platform certs"). This is
          # NOT the same `SSL_CERT_FILE` reassigned further down to mitm-
          # cache's own self-signed CA — that one is for Gradle/the JVM's
          # own requests *through* the proxy, set only after the proxy
          # already has a real upstream trust store of its own. A child
          # process launched via `&` snapshots the environment at that
          # exact moment — setting `SSL_CERT_FILE` any later than this
          # would have zero effect on it, no matter how much sooner that
          # later line runs relative to mitm-cache's own request handling.
          export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
          export NIX_SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
          # `--forget-redirects-from`/`--record-text` match nixpkgs' own
          # gradle/fetch-deps.nix recording invocation exactly — dropping
          # recorded redirects keeps the lockfile independent of whichever
          # CDN edge happened to answer during this one recording run, and
          # maven-metadata.xml needs its literal text (not just a hash)
          # since mkTauriApp regenerates it on every fetch rather than
          # replaying byte-for-byte (see mitm-cache's own fetch.nix).
          mitm-cache -l"$MITM_CACHE_ADDRESS" record \
            --reject '\.(md5|sha(1|256|512:?):?)$' \
            --forget-redirects-from '.*' \
            --record-text '/maven-metadata\.xml$' >&2 &
          mitmRecordPid=$!
          for i in $(seq 0 20); do
            kill -0 "$mitmRecordPid" 2>/dev/null || {
              echo "androidMitmRecord: mitm-cache exited early" >&2
              exit 1
            }
            curl -so /dev/null "$MITM_CACHE_ADDRESS" && break
            sleep 0.5
          done
          export MITM_CACHE_CA="$mitmRecordDir/ca.cer"
          export SSL_CERT_FILE="$MITM_CACHE_CA"
          export NIX_SSL_CERT_FILE="$MITM_CACHE_CA"
          export http_proxy="$MITM_CACHE_ADDRESS"
          export https_proxy="$MITM_CACHE_ADDRESS"
          mitmRecordKeystore="$mitmRecordDir/keystore"
          mitmRecordKsPwd=$(head -c10 /dev/random | base32)
          "${jdk21}/bin/keytool" -importcert -noprompt -file "$MITM_CACHE_CA" \
            -alias alias -keystore "$mitmRecordKeystore" -storepass "$mitmRecordKsPwd"
          # `androidPreBuild`'s own hijacked `gradlew` execs the raw
          # `gradle` binary directly (never through nixpkgs' `gradle`
          # setup-hook's own `gradle()` shell function, which is what
          # normally injects these same flags automatically) — `GRADLE_OPTS`
          # is read by the plain launcher itself, not just a daemon, so it
          # reaches every gradle invocation in this build (top-level and the
          # recursive `rustBuild*`-triggered ones alike) regardless.
          export GRADLE_OPTS="-Dhttp.proxyHost=$MITM_CACHE_HOST -Dhttp.proxyPort=$MITM_CACHE_PORT -Dhttps.proxyHost=$MITM_CACHE_HOST -Dhttps.proxyPort=$MITM_CACHE_PORT -Djavax.net.ssl.trustStore=$mitmRecordKeystore -Djavax.net.ssl.trustStorePassword=$mitmRecordKsPwd"
          popd >/dev/null
        '';
      installPhase = ''
        runHook preInstall
        kill -s SIGINT "$mitmRecordPid" 2>/dev/null || true
        for i in $(seq 0 20); do
          [ -s "$mitmRecordDir/out.json" ] && break
          sleep 1
        done
        mkdir -p $out
        # `-S`: canonical (sorted) key order, so this FOD's own hash tracks
        # the *set* of recorded url->hash pairs, not whatever order
        # concurrent requests happened to resolve in during this one
        # recording run.
        jq -S . "$mitmRecordDir/out.json" > $out/deps.json
        runHook postInstall
      '';
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      # Per-*variant*, not one shared value: `androidBuildCmd`'s `--debug`
      # flag (or lack of it) makes AGP resolve a genuinely different runtime
      # classpath, so a debug recording's `deps.json` content — and thus its
      # real content hash — legitimately differs from a release recording's.
      # Read from `androidDepsFile` itself (see its own comment above) so
      # `update-android-deps <app>` can update this in the one file it
      # already writes `dependencies` back into, instead of a second place. Falls
      # back to `lib.fakeHash` for a variant this app has never recorded
      # yet — the resulting *guaranteed* mismatch is exactly how the real
      # hash gets discovered the first time (see mitm-cache's own comment on
      # this dance).
      outputHash = androidDepsData.androidMitmRecordHash.${
        if release
        then "release"
        else "debug"
      } or lib.fakeHash;
    });

  cargoArtifacts =
    if isAndroid
    # crane's usual separate buildDepsOnly pre-warm pass only ever covers a
    # single (host) cargo target, not the 4 cross-compiled Android ABIs the
    # real build produces, so it buys nothing extra here — skipped, same as
    # `androidMitmRecord`'s own `cargoArtifacts = null`.
    then null
    else
      attrs.cargoArtifacts or (
        craneLib.buildDepsOnly (commonArgs
          // {
            preBuild =
              if isWindows
              then windowsPreBuild
              else commonPreBuild;
          })
      );

  buildCmd =
    "cargo tauri build --ci --config '${tauriConfigPatch}'"
    + lib.optionalString isWindows " --runner cargo-xwin --target x86_64-pc-windows-gnu"
    + lib.optionalString isLinux " --no-bundle";

  installCmd =
    if isWindows
    then ''
      mkdir -p $out
      cp -avr target/x86_64-pc-windows-gnu/release/bundle/nsis/* $out/ 2>/dev/null || true
    ''
    else ''
      mkdir -p $out/bin
      cp -v target/release/* $out/bin/ 2>/dev/null || true
    '';

  app = craneLib.mkCargoDerivation (commonArgs
    // {
      inherit cargoArtifacts;
      doInstallCargoArtifacts = false;
      buildPhaseCargoCommand =
        if isAndroid
        then androidBuildCmd
        else buildCmd;
      installPhase = ''
        runHook preInstall
        ${
          if isAndroid
          then androidInstallCmd
          else installCmd
        }
        runHook postInstall
      '';
      preBuild =
        if isAndroid
        then
          androidPreBuild
          + ''
            export GRADLE_USER_HOME=$HOME/.gradle
            # `mitmCacheConfigureHook` (mitm-cache's own setup hook, bundled
            # into `gradle`'s combined one — see default.nix's own
            # `wrapGradle`) and `gradleConfigureHook` (gradle's own) already
            # ran during `configurePhase`, in that order: the former started
            # a local replay proxy serving `androidMitmCache`'s fetched
            # artifacts and set `$MITM_CACHE_HOST`/`$MITM_CACHE_CA` etc
            # (plain shell vars, not `export`ed, but this is the same
            # continuous build script/shell those ran in, so they're still
            # readable here); the latter saw `$MITM_CACHE_CA` already set
            # and so built a Java trustStore for it (`$MITM_CACHE_KEYSTORE`/
            # `$MITM_CACHE_KS_PWD`, also plain vars) instead of falling back
            # to `--offline`. Neither ever reaches our own hijacked
            # `gradlew` though: that execs the raw `gradle` binary directly,
            # never through gradle's own setup-hook `gradle()` shell
            # function (the thing that would normally turn those into
            # `-Dhttp(s).proxyHost/Port`/`-Djavax.net.ssl.trustStore` JVM
            # flags automatically) — so this constructs the same flags
            # itself and exports them via `GRADLE_OPTS`, which (unlike a
            # command-line flag) is read by the plain launcher script itself
            # regardless of how it's invoked, reaching every gradle
            # invocation in this build (top-level and the recursive
            # `rustBuild*`-triggered ones alike).
            export GRADLE_OPTS="-Dhttp.proxyHost=$MITM_CACHE_HOST -Dhttp.proxyPort=$MITM_CACHE_PORT -Dhttps.proxyHost=$MITM_CACHE_HOST -Dhttps.proxyPort=$MITM_CACHE_PORT -Djavax.net.ssl.trustStore=$MITM_CACHE_KEYSTORE -Djavax.net.ssl.trustStorePassword=$MITM_CACHE_KS_PWD"
          ''
        else if isWindows
        then windowsPreBuild
        else commonPreBuild;
    }
    // lib.optionalAttrs isAndroid {mitmCache = androidMitmCache;}
    // lib.optionalAttrs (postInstall != "") {inherit postInstall;});
in
  lib.recursiveUpdate app {
    passthru = {
      inherit attrs releaseType pname rustSrc;
    };
  }
  # Top-level, not nested under `passthru` above: `passthru`'s own
  # attributes only get spliced onto a derivation's top level by
  # `mkDerivation` itself, as part of constructing the derivation in the
  # first place — `lib.recursiveUpdate` here runs *after* `app` already
  # exists, so a `passthru`-nested attribute at this point would stay
  # nested (reachable as `app.passthru.androidMitmRecord`, not
  # `app.androidMitmRecord`) instead of becoming reachable the way
  # nix/scripts.nix's `update-android-deps` script (a plain Nix-level
  # reference via `.drvPath`, not a `devenv build` CLI dotted-attribute
  # argument — see that file's own comment on why) needs — the exact same
  # reasoning `mkTauriFrontend.nix`'s own `frontendSrc` comment gives for
  # the same mistake.
  // lib.optionalAttrs isAndroid {
    inherit androidMitmCache androidMitmRecord androidDepsFile;
  }
