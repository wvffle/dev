{ lib, ... }:
src:
lib.cleanSourceWith {
  src = lib.cleanSource src;
  filter =
    path: type:
    !(builtins.any (r: (builtins.match r (baseNameOf path)) != null) [
      "justfile"
      "flake.lock"
      "devenv.lock"
      "devenv.yaml"
      "node_modules"
      ".env"
      ".envrc"
      ".venv"
      ".forgejo"
      ".github"
      ".direnv"
      ".devenv"
    ]);
}
