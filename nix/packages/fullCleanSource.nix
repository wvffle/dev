{lib, ...}: src: {
  # List of function (path -> type -> bool) OR string (regex matched
  # against baseNameOf). If ANY matches, the path is force-included,
  # bypassing deny and the default filter entirely. Checked first.
  allow ? [],
  # List of function OR string, same matching rules as `allow`. If ANY
  # matches (and no allow matched), the path is excluded. Checked second.
  deny ? [],
}: let
  # Normalize a single allow/deny entry to a (path: type: bool) predicate.
  # Strings are matched as regexes against the path's basename.
  toPredicate = p:
    if builtins.isFunction p
    then p
    else (path: type: builtins.match p (baseNameOf path) != null);

  matchesAny = preds: path: type:
    builtins.any (p: (toPredicate p) path type) preds;

  isAllowed = matchesAny allow;
  isDenied = matchesAny deny;

  defaultDenyNames = [
    "justfile"
    "flake.lock"
    "devenv.lock"
    "devenv.yaml"
    "devenv.nix"
    "flake.nix"
    "node_modules"
    "dist"
    ".dist"
    ".env"
    ".envrc"
    ".venv"
    ".forgejo"
    ".github"
    ".direnv"
    ".devenv"
  ];

  # Delegates to nixpkgs' own cleanSourceFilter (VCS metadata, editor
  # backups, nix-build result symlinks, *.o/*.so) plus our tooling cruft
  # list. Safe to delegate rather than reimplement, since `isAllowed` is
  # checked first and short-circuits before this is ever reached - so
  # cleanSourceFilter's *.o/*.so strip never blocks an explicit `allow`.
  defaultFilter = path: type:
    lib.cleanSourceFilter path type
    && !(builtins.any (r: builtins.match r (baseNameOf path) != null) defaultDenyNames);
in
  lib.cleanSourceWith {
    inherit src;
    filter = path: type:
      if isAllowed path type
      then true
      else if isDenied path type
      then false
      else defaultFilter path type;
  }
