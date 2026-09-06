{
  lib,
  fullCleanSource,
  mkTauriFrontend,
  crane,
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
  extraSrcPaths ? [],
  ...
}: let
  isWindows = target == "windows";
  isLinux = target == "linux";

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
    else "release";

  craneLib = crane.mkLib (
    if isWindows
    then pkgsCross.mingwW64
    else pkgs
  );

  # ---- Rust source ----

  rootCargoTomlPath = "${cleanSrc}/Cargo.toml";
  rootCargoToml =
    if builtins.pathExists rootCargoTomlPath
    then builtins.fromTOML (builtins.readFile rootCargoTomlPath)
    else {};
  workspaceMembers =
    if builtins.pathExists rootCargoTomlPath
    then rootCargoToml.workspace.members or []
    else [];

  relOf = path: lib.removePrefix (toString src + "/") (toString path);
  isUnderCrateDir = rel: crateDir: rel == crateDir || lib.hasPrefix "${crateDir}/" rel;

  splitPath = p: lib.filter (s: s != "" && s != ".") (lib.splitString "/" p);
  joinPath = parts: lib.concatStringsSep "/" parts;

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
    step [tauriRoot];

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
      inherit src tauriRoot frontendRoot extraSrcPaths tauriConf;
      version = resolvedVersion;
    });

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
      else [cargo-tauri.hook pkg-config wrapGAppsHook4]
    )
    ++ nativeBuildInputs;

  platformBuildInputs =
    (
      if isWindows
      then [openssl]
      else [openssl webkitgtk_4_1 glib-networking]
    )
    ++ buildInputs;

  commonArgs =
    {
      inherit pname;
      version = resolvedVersion;
      src = rustSrc;
      cargoLock = lockFile;
      strictDeps = true;
      doCheck = false;
      nativeBuildInputs = platformNativeInputs;
      buildInputs = platformBuildInputs;
      NIX_CFLAGS_COMPILE = lib.optionalString isWindows "-Wno-error=stringop-overflow";
    }
    // env
    // lib.optionalAttrs updater.enable {
      TAURI_SIGNING_PRIVATE_KEY = updater.privateKey;
      TAURI_SIGNING_PRIVATE_KEY_PASSWORD = updater.privateKeyPassword;
    };

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

  cargoArtifacts =
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
      buildPhaseCargoCommand = buildCmd;
      installPhase = ''
        runHook preInstall
        ${installCmd}
        runHook postInstall
      '';
      preBuild =
        if isWindows
        then windowsPreBuild
        else commonPreBuild;
    }
    // lib.optionalAttrs (postInstall != "") {
      inherit postInstall;
    });
in
  lib.recursiveUpdate app {
    passthru = {
      inherit attrs releaseType pname rustSrc;
    };
  }
