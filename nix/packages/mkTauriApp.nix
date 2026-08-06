{
  lib,

  fullCleanSource,
  mkTauriFrontend,

  craneLib,

  rustPlatform,

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
}:
{
  src,
  tauriRoot ? "src-tauri",
  tauriConf ? builtins.fromJSON (builtins.readFile "${src}/${tauriRoot}/tauri.conf.json"),

  lockFile ?
    if builtins.pathExists "${src}/Cargo.lock" then
      "${src}/Cargo.lock"
    else
      "${src}/${tauriRoot}/Cargo.lock",

  frontend ? mkTauriFrontend {
    inherit src tauriRoot;
  },

  target ? "linux",
  nsisTauriUtils ? {
    version = "0.5.2";
    hash = "sha256-8+mw1Dtm+msF0vpN5FR1F6PsC8CxTePDSdgXRlu/erQ=";
  },
  cargoArtifacts ? null,
  craneArgs ? {},
  cargoRoot ? null,
  ...
}@attrs:
let
  isWindows = target == "windows";
  rustPlatform' = if isWindows then pkgsCross.mingwW64.rustPlatform else rustPlatform;
  tauriSrc = src + "/" + tauriRoot;
  actualCargoRoot = if cargoRoot != null then cargoRoot else tauriSrc;

  craneLib' = if isWindows then craneLib.mkLib pkgsCross.mingwW64 else craneLib;

  tauriConfig = builtins.toJSON (
    lib.recursiveUpdate tauriConf {
      build = {
        frontendDist = "${frontend}";
        beforeBuildCommand = "";
      };
    }
  );

  nsis-tauri-utils-dll = fetchurl {
    url = "https://github.com/tauri-apps/nsis-tauri-utils/releases/download/nsis_tauri_utils-v${nsisTauriUtils.version}/nsis_tauri_utils.dll";
    inherit (nsisTauriUtils) hash;
  };

  resolvedCargoArtifacts =
    if cargoArtifacts != null then
      cargoArtifacts
    else
      craneLib'.buildDepsOnly {
        inherit lockFile;
        src = fullCleanSource src;
        cargoRoot = actualCargoRoot;
        cargoLock = lockFile;
        strictDeps = true;
        nativeBuildInputs = [ pkg-config ];
        buildInputs = lib.optionals (!isWindows) [
          openssl
          webkitgtk_4_1
          glib-networking
        ];
        NIX_CFLAGS_COMPILE = lib.optionalString isWindows "-Wno-error=stringop-overflow";
      };

  mkLinuxBuild = craneLib.mkCargoDerivation (
    {
      pname = "${tauriConf.productName}-${target}";
      version = tauriConf.version;
      src = fullCleanSource src;
      cargoDeps = craneLib.importCargoLock { inherit lockFile; };
      cargoRoot = actualCargoRoot;
      cargoLock = lockFile;
      strictDeps = true;

      nativeBuildInputs = [
        cargo-tauri.hook
        pkg-config
        wrapGAppsHook4
      ];

      buildInputs = [
        openssl
        webkitgtk_4_1
        glib-networking
      ];

      inherit resolvedCargoArtifacts;

      TAURI_CONFIG = tauriConfig;
      CARGO_TARGET_DIR = "$PWD/target";

      NIX_CFLAGS_COMPILE = "";

      buildPhaseCargoCommand = "cargo tauri build --no-bundle ${tauriConf.build.beforeBuildCommand}";

      installPhase = # bash
        ''
          runHook preInstall

          mkdir -p $out/bin
          cp -v target/release/* $out/bin/

          runHook postInstall
        '';

      doInstallCargoArtifacts = false;
    }
    // craneArgs
  );

  mkWindowsBuild = craneLib'.mkCargoDerivation (
    {
      pname = "${tauriConf.productName}-${target}";
      version = tauriConf.version;
      src = fullCleanSource src;
      cargoDeps = craneLib'.importCargoLock { inherit lockFile; };
      cargoRoot = actualCargoRoot;
      cargoLock = lockFile;
      strictDeps = true;

      nativeBuildInputs = [
        pkg-config
        cargo-xwin
        nasm
        ninja
        cmake
        nsis
      ];

      buildInputs = [
        openssl
        webkitgtk_4_1
        glib-networking
      ];

      inherit resolvedCargoArtifacts;

      CARGO_TARGET_DIR = "$PWD/target";

      NIX_CFLAGS_COMPILE = "-Wno-error=stringop-overflow";

      preBuild = # bash
        ''
          runHook preBuild

          # Fetch `nsis_tauri_utils.dll` file and insert it into the cache.
          export HOME="$(mktemp -d)"
          mkdir -p $HOME/.cache/tauri/NSIS/Plugins/x86-unicode/additional
          cp -v ${nsis-tauri-utils-dll} $HOME/.cache/tauri/NSIS/Plugins/x86-unicode/additional/nsis_tauri_utils.dll

          # Let stdenv handle stripping, for consistency and to not break separateDebugInfo.
          export CARGO_PROFILE_RELEASE_STRIP=false

          runHook postBuild
        '';

      buildPhaseCargoCommand = "cargo tauri build --no-bundle --target x86_64-pc-windows-gnu --offline";

      installPhase = # bash
        ''
          runHook preInstall

          mkdir -p $out/
          cp -avr target/x86_64-pc-windows-gnu/release/bundle/nsis/* $out/

          runHook postInstall
        '';

      doInstallCargoArtifacts = false;
    }
    // craneArgs
  );

  app = if isWindows then mkWindowsBuild else mkLinuxBuild;
in
rustPlatform'.buildRustPackage (
  lib.recursiveUpdate {
    inherit app;
    buildCommand = # bash
      ''
        cp -r ${app}/. $out
      '';
    passthru = { inherit attrs; };
  } attrs
)
