{
  description = "mkRustESPFirmware example: std (esp-idf-svc)";

  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    dev.url = "path:../../..";
  };

  outputs = {
    nixpkgs,
    dev,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      overlays = [dev.overlays.default];
    };
  in {
    packages.${system}.default = pkgs.mkRustESPFirmware {src = ./.;};
  };
}
