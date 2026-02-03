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
        mkTauriPackage = import prev.callPackage ./packages/mkTauriPackage.nix;
        mkTauriFrontend = import prev.callPackage ./packages/mkTauriFrontend.nix;

        mkPnpmPackage =
          { src, ... }@args:
          pnpm2nix.packages.${final.stdenv.hostPlatform.system}.mkPnpmPackage args
          // {
            src = final.fullCleanSource src;
          };

        fullCleanSource =
          src:
          prev.lib.cleanSourceWith {
            src = prev.lib.cleanSource src;
            filter =
              name: type:
              let
                basename = baseNameOf (toString name);
              in
              !(
                basename == "flake.lock"
                || basename == "devenv.lock"
                || basename == "node_modules"
                || basename == ".forgejo"
                || prev.lib.hasSuffix ".nix" basename
              );
          };
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
