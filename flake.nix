{
  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
  in {
    templates = rec {
      slidev = {
        path = ./templates/slidev;
        description = "A slidev presentation";
      };

      slides = slidev;
    };

    devShells.${system} = rec {
      sci = import ./shells/sci.nix {inherit pkgs;};
      science = sci;
      jupyter = sci;
      python = sci;
      py = sci;
    };
  };
}
