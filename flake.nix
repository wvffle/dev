{
  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    pnpm2nix.url = "github:FliegendeWurst/pnpm2nix-nzbr";
    pnpm2nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, pnpm2nix, ... }:
    let
      forAllSystems = with nixpkgs.lib; (genAttrs systems.flakeExposed);
    in
    {
      templates = rec {
        slidev = {
          path = ./templates/slidev;
          description = "A slidev presentation";
        };

        slides = slidev;
      };

      overlays.default = final: prev: {
        fullCleanSource = import ./packages/fullCleanSource.nix { inherit (prev) lib; };
        mkTauriApp = prev.callPackage import ./packages/mkTauriApp.nix;
        mkTauriFrontend = prev.callPackage import ./packages/mkTauriFrontend.nix;
        mkPnpmPackage = prev.callPackage (
          import ./packages/mkPnpmPackage.nix {
            inherit (final) fullCleanSource stdenv;
            inherit pnpm2nix;
          }
        );
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        rec {
          sci = import ./shells/sci.nix { inherit pkgs; };
          science = sci;
          jupyter = sci;
          python = sci;
          py = sci;
        }
      );
    };
}
