{
  lib,

  fullCleanSource,
  mkTauriFrontend,

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
}:
let
  isWindows = target == "windows";
  rustPlatform' = if isWindows then pkgsCross.mingwW64.rustPlatform else rustPlatform;
in
rustPlatform'.buildRustPackage {
  pname = "${tauriConf.productName}-${target}";
  version = tauriConf.version;
  src = fullCleanSource src;

  cargoDeps = rustPlatform'.importCargoLock {
    inherit lockFile;
  };

  nativeBuildInputs = [
    cargo-tauri.hook
    pkg-config
  ]
  ++ lib.optionals (!isWindows) [
    wrapGAppsHook4
  ]
  ++ lib.optionals isWindows [
    cargo-xwin
    nasm
    ninja
    cmake
    nsis
  ];

  buildInputs = lib.optionals (!isWindows) [
    openssl
    webkitgtk_4_1
    glib-networking
  ];

  cargoRoot = ".";

  # Ignore aws-lc-sys gcc error:
  #   In function 'OPENSSL_memcpy',
  #   error: 'memcpy' specified bound between 18446744071562067968 and 18446744073709551615 exceeds maximum object size 9223372036854775807 [-Werror=stringop-overflow=]
  NIX_CFLAGS_COMPILE = lib.optionalString isWindows "-Wno-error=stringop-overflow";

  postPatch = # bash
    ''
      # Replace frontend dist directory with frontend derivation path.
      substituteInPlace ${tauriRoot}/tauri.conf.json \
        --replace-warn '"frontendDist": "${tauriConf.build.frontendDist}"' '"frontendDist": "${frontend}"'

      # Remove frontend build command.
      substituteInPlace ${tauriRoot}/tauri.conf.json \
        --replace-warn '"${tauriConf.build.beforeBuildCommand}"' '""'
    '';

  tauriBuildFlags = lib.optionals isWindows [
    "--runner"
    "cargo-xwin"
  ];

  buildPhase =
    let
      inherit (rustPlatform'.cargoBuildHook) setEnv;
      nsis-tauri-utils-dll = fetchurl {
        url = "https://github.com/tauri-apps/nsis-tauri-utils/releases/download/nsis_tauri_utils-v${nsisTauriUtils.version}/nsis_tauri_utils.dll";
        inherit (nsisTauriUtils) hash;
      };
    in
    lib.optionalString isWindows # bash
      ''
        runHook preBuild

        # Fetch `nsis_tauri_utils.dll` file and insert it into the cache.
        export "HOME"="$(mktemp -d)"
        mkdir -p $HOME/.cache/tauri/NSIS/Plugins/x86-unicode/additional
        cp -v ${nsis-tauri-utils-dll} $HOME/.cache/tauri/NSIS/Plugins/x86-unicode/additional/nsis_tauri_utils.dll

        # Let stdenv handle stripping, for consistency and to not break separateDebugInfo.
        export "CARGO_PROFILE_RELEASE_STRIP"=false

        ${setEnv} cargo tauri build --runner cargo-xwin --target x86_64-pc-windows-gnu -- -j "$NIX_BUILD_CORES"  --target x86_64-pc-windows-gnu --offline

        runHook postBuild
      '';

  installPhase =
    lib.optionalString isWindows # bash
      ''
        runHook preInstall

        mkdir -p $out/
        cp -avr target/x86_64-pc-windows-gnu/release/bundle/nsis/* $out/

        runHook postInstall
      '';
}
