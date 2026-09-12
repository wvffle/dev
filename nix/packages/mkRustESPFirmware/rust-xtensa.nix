# A prebuilt Xtensa-enabled Rust toolchain (rustc/cargo forked by Espressif
# to target ESP32's Xtensa CPU — mainline rustc has no Xtensa backend at
# all, so this can't be an ordinary nixpkgs/fenix toolchain). Consumed by
# ../mkRustESPFirmware.nix via `craneLib.overrideToolchain`.
#
# `mk-component-set.nix`/`mk-aggregated.nix` are vendored, with one small
# patch (see the comment inside mk-component-set.nix), from
# https://github.com/milas/esp-flake (itself adapted from nixpkgs' own
# internal rust-bin component installer) rather than taken as a flake
# input: that flake pins a stale Rust release (1.83.0.1, Dec 2024) whose
# ecosystem of transitive crates.io deps has since moved on to requiring
# edition2024 (stabilized in upstream Rust 1.85), so using it unpatched
# fails dependency resolution. Version/hashes below point at the current
# https://github.com/esp-rs/rust-build release instead — bump `version`
# and re-fetch the two hashes (`nix-prefetch-url --type sha256 <url>`) to
# update.
{
  lib,
  stdenv,
  rust,
  fetchurl,
  callPackage,
}: let
  version = "1.97.0.0";

  # FIXME (upstream nixpkgs issue #146274): wasm32-wasi's target triple
  # needs a manual override; rust.toRustTarget doesn't handle it.
  toRustTarget = platform:
    if platform.isWasi
    then "${platform.parsed.cpu.name}-wasi"
    else rust.toRustTarget platform;

  removeNulls = set:
    removeAttrs set
    (lib.filter (name: set.${name} == null) (lib.attrNames set));

  mkComponentSet = callPackage ./mk-component-set.nix {
    inherit toRustTarget removeNulls;
  };
  mkAggregated = callPackage ./mk-aggregated.nix {};

  components = mkComponentSet {
    inherit version;
    renames = {};
    platform = "x86_64-linux";
    srcs = {
      rustc = fetchurl {
        url = "https://github.com/esp-rs/rust-build/releases/download/v${version}/rust-${version}-x86_64-unknown-linux-gnu.tar.xz";
        sha256 = "16cx7r38skkqs4y0lh50wq2x9338xq8ni3rqhrnzzs91jbkgx6x9";
      };
      rust-src = fetchurl {
        url = "https://github.com/esp-rs/rust-build/releases/download/v${version}/rust-src-${version}.tar.xz";
        sha256 = "0wwbqql8mrkrb61zav4y3vhrrs93mm7m8ms6s322wcwgky5ni3an";
      };
    };
  };
in
  assert stdenv.system == "x86_64-linux"; # only host platform this is fetched for
    mkAggregated {
      pname = "rust-xtensa";
      inherit version;
      date = null;
      availableComponents = components;
      selectedComponents = [components.rustc components.rust-src];
    }
