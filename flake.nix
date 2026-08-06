{
  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    pnpm2nix.url = "github:FliegendeWurst/pnpm2nix-nzbr";
    pnpm2nix.inputs.nixpkgs.follows = "nixpkgs";
    crane.url = "github:ipetkov/crane";
  };

  outputs = {
    nixpkgs,
    pnpm2nix,
    crane,
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
        pkgs = prev;
      };
      mkPnpmPackage = prev.callPackage ./nix/packages/mkPnpmPackage.nix {
        inherit pnpm2nix;
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
