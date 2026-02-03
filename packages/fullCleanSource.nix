{ lib, ... }:
src:
lib.cleanSourceWith {
  src = lib.cleanSource src;
  filter =
    name: type:
    let
      basename = baseNameOf (toString name);
    in
    !(
      basename == "flake.lock"
      || basename == "devenv.lock"
      || basename == "devenv.yaml"
      || basename == "node_modules"
      || basename == ".envrc"
      || basename == ".forgejo"
      || lib.hasSuffix ".nix" basename
    );
}
