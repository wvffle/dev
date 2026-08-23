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
  ...
}: let
  isWindows = target == "windows";
  isLinux = target == "linux";
  resolvedVersion = tauriConf.version;
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
  workspaceMembers =
    if builtins.pathExists rootCargoTomlPath
    then (builtins.fromTOML (builtins.readFile rootCargoTomlPath)).workspace.members or []
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
  frontend = attrs.frontend or (mkTauriFrontend {inherit src tauriRoot;});

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
