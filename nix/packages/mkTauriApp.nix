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
  tauriConf ? builtins.fromJSON (builtins.readFile "${src}/${tauriRoot}/tauri.conf.json"),
  # Last-resort version fallback, used only when tauri.conf.json omits
  # version and it can't be resolved from ${tauriRoot}/Cargo.toml either
  # (directly, or via `version.workspace = true` pointing at the root
  # Cargo.toml's [workspace.package].version).
  version ? null,
  lockFile ?
    if builtins.pathExists "${src}/Cargo.lock"
    then "${src}/Cargo.lock"
    else "${src}/${tauriRoot}/Cargo.lock",
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

  # Tauri itself falls back to the package Cargo.toml's version when
  # tauri.conf.json omits it, and that version may in turn be inherited
  # from the workspace via `version.workspace = true` (parsed as the
  # table { workspace = true; }). Both Cargo.toml reads stay inside `src`
  # (no walking above it, which doesn't work: `src` is a Nix store path
  # containing only the given subtree, so a parent directory outside it
  # isn't the real workspace root even if one exists on disk).
  tauriCargoTomlPath = "${src}/${tauriRoot}/Cargo.toml";
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

  rootCargoTomlPath = "${src}/Cargo.toml";
  rootCargoToml =
    if builtins.pathExists rootCargoTomlPath
    then builtins.fromTOML (builtins.readFile rootCargoTomlPath)
    else {};
  workspaceMembers =
    if builtins.pathExists rootCargoTomlPath
    then rootCargoToml.workspace.members or []
    else [];

  rustCrateDirs = lib.unique ([tauriRoot] ++ workspaceMembers);

  relOf = path: lib.removePrefix (toString src + "/") (toString path);
  isUnderCrateDir = rel: crateDir: rel == crateDir || lib.hasPrefix "${crateDir}/" rel;

  isRustSrcPath = path: type: let
    rel = relOf path;
  in
    rel == "Cargo.toml" || rel == "Cargo.lock" || lib.any (isUnderCrateDir rel) rustCrateDirs;

  # Whitelist: allow claims everything under a rust crate dir (bypassing
  # the default filter's *.o/*.so strip, needed for vendored prebuilt
  # libs like elzabdr.so); deny is the exact negation, making this an
  # exclusive whitelist rather than "default plus exceptions".
  rustSrc = fullCleanSource src {
    allow = [isRustSrcPath];
    deny = [(path: type: !(isRustSrcPath path type))];
  };

  # Frontend/Rust source splitting now lives inside mkTauriFrontend
  # itself, since it already reads tauriConf/tauriRoot.
  frontend =
    attrs.frontend or (mkTauriFrontend {
      inherit src tauriRoot frontendRoot extraSrcPaths;
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
