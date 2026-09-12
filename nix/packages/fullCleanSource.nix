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
    # Gradle/AGP build-artifact dirs — e.g. a Tauri android target's own
    # `gen/android/{app,buildSrc}/build` and `.gradle` caches, populated by
    # running a real build directly against a live checkout (outside a
    # sandboxed derivation). No tracked source lives under a directory
    # literally named this in either repo (confirmed via `git ls-files`),
    # same reasoning as `node_modules`/`dist` above — and unlike those,
    # these can reach many thousands of files, making every mkTauriApp
    # call that includes this subtree (any of them, since `src` is
    # typically the whole monorepo root) walk/copy all of them for
    # nothing every single evaluation.
    "build"
    ".gradle"
    # Cargo's own build-artifact dir — same reasoning as `build`/`.gradle`
    # above: a live local `cargo build`/`cargo check` run directly against
    # a checkout (outside a sandboxed derivation) leaves tens of thousands
    # of files here for every mkTauriApp caller to walk on every
    # evaluation, and no tracked source lives under a dir named this in
    # either repo (confirmed via `git ls-files`).
    "target"
    # embuild's (esp-idf-sys's build-time dependency) self-managed ESP-IDF
    # checkout + toolchain download dir, populated by running `cargo
    # build` directly against an mkRustESPFirmware crate's checkout
    # outside a sandboxed derivation — same reasoning as `target` above,
    # except worse: this one reaches multiple GB (a full ESP-IDF clone
    # plus toolchain archives), not just many files. Found the hard way:
    # left behind by local testing, it got silently copied into a
    # `qr-scanner-firmware` build's source derivation and made every
    # evaluation touching that source needlessly slow.
    ".embuild"
    # GrayMatter's (Claude Code's memory MCP server) per-project state
    # dir — not build output, but same reasoning as everything else here:
    # it's local machine/session state, no tracked source ever lives
    # under a directory named this, and it has nothing to contribute to
    # any build's source.
    ".graymatter"
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
