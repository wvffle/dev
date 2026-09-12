{
  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    pnpm2nix.url = "github:FliegendeWurst/pnpm2nix-nzbr";
    pnpm2nix.inputs.nixpkgs.follows = "nixpkgs";
    crane.url = "github:ipetkov/crane";
    # mkTauriApp's android target needs rustc/std for the 4 Android ABIs
    # (aarch64/armv7/i686/x86_64-*-android*) — plain nixpkgs only ships a
    # single-target rustc, so this is what supplies the rest as ordinary
    # fetchurl-backed derivations (Rust's own prebuilt component archives,
    # the same ones `rustup target add` would download), fully usable
    # inside a sandboxed `nix build`.
    fenix.url = "github:nix-community/fenix";
    fenix.inputs.nixpkgs.follows = "nixpkgs";
    # mkRustESPFirmware's ESP-IDF C SDK/toolchain. Deliberately NOT
    # `follows: nixpkgs`: its own packaging (nix/esp-idf/tools.nix)
    # hardcodes a `python310` callPackage argument that no longer exists
    # once `nixpkgs` here drifts far enough ahead (this repo tracks the
    # rolling channel) — letting it use its own pinned nixpkgs sidesteps
    # that version skew entirely.
    esp-dev.url = "github:mirrexagon/nixpkgs-esp-dev";
  };

  outputs = {
    nixpkgs,
    pnpm2nix,
    crane,
    fenix,
    esp-dev,
    ...
  }: let
    forAllSystems = with nixpkgs.lib; (genAttrs systems.flakeExposed);
  in {
    templates = rec {
      slidev = {
        path = ./nix/templates/slidev;
        description = "A slidev presentation";
      };

      slides = slidev;
    };

    overlays.default = final: prev: {
      fullCleanSource = import ./nix/packages/fullCleanSource.nix {inherit (prev) lib;};
      mkTauriFrontend = prev.callPackage ./nix/packages/mkTauriFrontend.nix {};
      mkTauriApp = prev.callPackage ./nix/packages/mkTauriApp.nix {
        crane = crane;
        fenix = fenix;
        pkgs = prev;
      };
      mkPnpmPackage = prev.callPackage ./nix/packages/mkPnpmPackage.nix {
        inherit pnpm2nix;
      };
      mkRustESPFirmware = prev.callPackage ./nix/packages/mkRustESPFirmware.nix {
        inherit crane;
        espDev = esp-dev;
        pkgs = prev;
      };
    };

    devShells = forAllSystems (
      system: let
        pkgs = import nixpkgs {inherit system;};
      in rec {
        sci = import ./nix/shells/sci.nix {inherit pkgs;};
        science = sci;
        jupyter = sci;
        python = sci;
        py = sci;
      }
    );
  };
}
