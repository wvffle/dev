# Builds a Rust firmware crate for an Xtensa ESP32 (ESP32/S2/S3) target,
# fully hermetically (no espup/network access needed at build time —
# everything embuild/esp-idf-sys would otherwise fetch itself comes from
# Nix instead). Covers both esp-rs "types" of firmware — see `type` below.
#
# Supporting pieces, both Xtensa-specific (this builder doesn't cover
# RISC-V ESP32 variants, which don't need any of this — plain upstream
# Rust already has a RISC-V backend):
#   - ./mkRustESPFirmware/rust-xtensa.nix: the Xtensa-enabled Rust
#     compiler fork, since mainline rustc has no Xtensa backend at all.
#     Needed by both `type`s (nostd's `-Zbuild-std` of core/alloc needs it
#     exactly as much as std's std/panic_abort does).
#   - `espDev` (github:mirrexagon/nixpkgs-esp-dev, a flake input on its
#     own pinned nixpkgs — see flake.nix's own comment on why not
#     `follows: nixpkgs`): the ESP-IDF C SDK + toolchain esp-idf-sys's
#     build script needs, supplied via `ESP_IDF_TOOLS_INSTALL_DIR=fromenv`
#     so it doesn't try to install anything itself over the network. Only
#     pulled in for `type = "std"` — a nostd (esp-hal) crate never touches
#     esp-idf-sys/ESP-IDF at all, so building it a multi-GB C SDK closure
#     it can't even use would be pure waste.
{
  lib,
  pkgs,
  fullCleanSource,
  crane,
  espDev,
}: {
  src,
  # Relative path from `src` to the firmware crate's own root (the
  # directory holding its Cargo.toml) — same convention as mkTauriApp's
  # `tauriRoot`, for a firmware crate that's one member of a larger repo.
  cargoRoot ? ".",
  pname ? null,
  version ? null,
  # "std": esp-idf-svc/esp-idf-sys, running atop ESP-IDF/FreeRTOS — needs
  #   ESP-IDF + ldproxy (see above).
  # "nostd": esp-hal, bare-metal, no ESP-IDF at all — just the Xtensa
  #   toolchain, linking directly via the target's own default linker.
  # See examples/esp32-firmware/{std,nostd} for a minimal crate of each.
  type ? "std",
  # Extra crane.buildPackage nativeBuildInputs/env, merged with (not
  # replacing) this builder's own defaults below.
  extraNativeBuildInputs ? [],
  extraEnv ? {},
}:
  assert lib.assertOneOf "type" type ["std" "nostd"]; let
    crateRoot = "${fullCleanSource src {}}/${cargoRoot}";
    crateToml = builtins.fromTOML (builtins.readFile "${crateRoot}/Cargo.toml");

    rust-xtensa = pkgs.callPackage ./mkRustESPFirmware/rust-xtensa.nix {};
    ldproxy = pkgs.callPackage ./mkRustESPFirmware/ldproxy.nix {};
    craneLib = (crane.mkLib pkgs).overrideToolchain (_: rust-xtensa);

    # `esp-idf-xtensa` pulls in esptool/esp-coredump, whose Python dep
    # `ecdsa` is marked insecure (CVE-2024-23342) — see
    # https://github.com/mirrexagon/nixpkgs-esp-dev/issues/109.
    espPkgs = import espDev.inputs.nixpkgs {
      inherit (pkgs) system;
      overlays = [espDev.overlays.default];
      config.permittedInsecurePackages = ["python3.13-ecdsa-0.19.1"];
    };
  in
  craneLib.buildPackage {
    pname =
      if pname != null
      then pname
      else crateToml.package.name;
    version =
      if version != null
      then version
      else crateToml.package.version;
    src = crateRoot;
    strictDeps = true;
    doCheck = false; # cross-compiled for Xtensa; can't run the crate's own tests on the build host
    # crane defaults CARGO_PROFILE to "release" already — no cargoExtraArgs needed.
    #
    # `cargoArtifacts = null` forces a single-phase build (no separate
    # buildDepsOnly derivation providing a prebuilt `target/` to seed
    # this one with). Confirmed by direct testing: with the normal
    # two-phase build, esp-idf-sys's `links = "esp_idf"`-propagated
    # `cargo:rustc-link-arg` directives (hundreds of them — every ESP-IDF
    # static lib/linker script/`--ldproxy-linker`) never reach the final
    # binary's rustc invocation once its cargoArtifacts come from a
    # separate derivation's `target/` copied in — `ldproxy` then runs
    # with none of its required arguments and panics. A from-scratch
    # single-phase build doesn't hit whatever cross-derivation cargo
    # fingerprint/replay gap causes that, at the cost of no deps caching.
    cargoArtifacts = null;
    # The crate's own Cargo.lock alone isn't enough: `-Zbuild-std` (needed
    # since there's no prebuilt std for any Xtensa target — see the
    # consuming crate's own `.cargo/config.toml`) recompiles std itself
    # from rust-xtensa's bundled rust-src, which resolves against its OWN
    # separate Cargo.lock (rustc-demangle, gimli, object, ...) — vendor
    # both into one directory rather than letting crane auto-vendor just
    # the firmware crate's.
    cargoVendorDir = craneLib.vendorMultipleCargoDeps {
      cargoLockList = [
        "${crateRoot}/Cargo.lock"
        "${rust-xtensa}/lib/rustlib/src/rust/library/Cargo.lock"
      ];
    };
    nativeBuildInputs =
      (
        if type == "std"
        then [ldproxy espPkgs.esp-idf-xtensa espPkgs.python3]
        else []
      )
      ++ extraNativeBuildInputs;
    env =
      (
        if type == "std"
        then {
          LIBCLANG_PATH = "${pkgs.libclang.lib}/lib";
          # esp-idf-xtensa's bundled esp-clang is a prebuilt binary linked
          # against the pre-2.14 libxml2 SONAME (`libxml2.so.2`) — nixpkgs
          # has since moved past it (`libxml2.so.16`), so autoPatchelf
          # can't paper over this one; `libxml2_13` is the last nixpkgs
          # alias still built against the old SONAME.
          LD_LIBRARY_PATH = lib.makeLibraryPath [pkgs.libxml2_13 pkgs.zlib pkgs.stdenv.cc.cc.lib];
          # Tells esp-idf-sys/embuild that esp-idf-xtensa above (on PATH
          # via nativeBuildInputs, IDF_PATH set by its setup hook) is the
          # whole toolchain to use as-is — skip its own network-fetching
          # installer, which would fail as soon as it fell back to it
          # since a sandboxed Nix build has no network access.
          ESP_IDF_TOOLS_INSTALL_DIR = "fromenv";
        }
        else {}
      )
      // extraEnv;
  }
