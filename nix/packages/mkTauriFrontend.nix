{
  mkPnpmPackage,
  fullCleanSource,
  lib,
  ...
}: {
  src,
  tauriRoot ? "src-tauri",
  # Interpolating "${src}/..." directly would addToStore the whole,
  # *unfiltered* src as a side effect (string interpolation of a path
  # always copies its entire root, not just the accessed subpath) - so
  # this and rootCargoTomlPath below go through fullCleanSource first,
  # which excludes .devenv (and other cruft) during the copy instead of
  # racing a live devenv process's sqlite state files. mkTauriApp forwards
  # its already-resolved tauriConf here, so this default only fires on a
  # standalone call.
  tauriConf ? builtins.fromJSON (builtins.readFile "${fullCleanSource src {}}/${tauriRoot}/tauri.conf.json"),
  # Optional; when absent, falls back to tauriConf.version. mkTauriApp
  # passes its resolved version so the frontend package stays in sync.
  version ? null,
  # Directory (relative to src) the frontend build is scoped to - everything
  # outside it is excluded, so unrelated projects in a monorepo don't bust
  # the frontend build cache or bloat its source closure. Defaults to
  # tauriRoot's parent, e.g. "apps/desktop" for tauriRoot =
  # "apps/desktop/tauri"; "." (the whole src) for a standalone project
  # where tauriRoot sits at src's top level, preserving old behaviour.
  frontendRoot ? builtins.dirOf tauriRoot,
  # Extra paths (relative to src) to keep despite being outside
  # frontendRoot - e.g. sibling pnpm-workspace packages that frontendRoot
  # depends on via `workspace:*`. Nix has no YAML parser to resolve
  # pnpm-workspace.yaml globs automatically, so list them explicitly.
  extraSrcPaths ? [],
}: let
  isNonEmptyVersion = v: v != null && v != "" && v != true;
  cleanSrc = fullCleanSource src {};
  rootCargoTomlPath = "${cleanSrc}/Cargo.toml";
  workspaceMembers =
    if builtins.pathExists rootCargoTomlPath
    then (builtins.fromTOML (builtins.readFile rootCargoTomlPath)).workspace.members or []
    else [];

  rustCrateDirs = lib.unique ([tauriRoot] ++ workspaceMembers);

  relOf = path: lib.removePrefix (toString src + "/") (toString path);
  isUnderDir = rel: dir: dir == "." || rel == dir || lib.hasPrefix "${dir}/" rel;
  isUnderCrateDir = isUnderDir;

  # Root manifests always kept regardless of frontendRoot: the pnpm ones
  # are needed for pnpm2nix to resolve the workspace at all, and
  # Cargo.toml is a common single-source-of-truth the frontend's own
  # build config reads from directly (e.g. a vite.config.ts pulling the
  # app version from [workspace.package].version, to stay in sync with
  # what mkTauriApp itself resolves the Rust version from).
  rootManifests = ["package.json" "pnpm-lock.yaml" "pnpm-workspace.yaml" "Cargo.toml"];

  # Directories that must be reachable via traversal - cleanSourceWith
  # calls the filter on directory nodes too, so every ancestor of a kept
  # path needs to pass or the walk never descends far enough to see it
  # (this is why tauriRoot itself, e.g. "apps/desktop/tauri", must pass
  # even though its Rust contents are excluded below).
  allowRoots = [frontendRoot "${tauriRoot}/tauri.conf.json"] ++ extraSrcPaths;
  isAncestorOfAllowRoot = rel: lib.any (target: lib.hasPrefix "${rel}/" target) allowRoots;

  isFrontendSrcPath = path: type: let
    rel = relOf path;
  in
    # tauri.conf.json is explicitly kept even though it lives inside a Rust
    # crate dir, which is excluded below.
    rel
    == "${tauriRoot}/tauri.conf.json"
    || lib.elem rel rootManifests
    || lib.any (isUnderDir rel) extraSrcPaths
    || isAncestorOfAllowRoot rel
    || (isUnderDir rel frontendRoot && !(lib.any (isUnderCrateDir rel) rustCrateDirs) && rel != "target" && !(lib.hasPrefix "target/" rel));
in
  mkPnpmPackage {
    pname = "${tauriConf.productName}-frontend";
    version =
      if tauriConf ? version && isNonEmptyVersion tauriConf.version
      then toString tauriConf.version
      else version;

    src = fullCleanSource src {
      allow = [isFrontendSrcPath];
      deny = [(path: type: !(isFrontendSrcPath path type))];
    };

    # beforeBuildCommand is authored assuming CWD is the frontend project
    # itself (as it would be if you `cd apps/desktop && cargo tauri build`
    # normally) - pnpm2nix's plain `scriptFull` otherwise runs it verbatim
    # at src's root, which in a monorepo is the wrong directory (e.g. its
    # package.json has no matching script at all, or pnpm's workspace-root
    # script fallback recurses into unrelated packages instead). The cd
    # must stay inside a subshell - stdenv runs every phase in one
    # continuous script, so a bare `cd` here would otherwise leak into
    # installPhase too and break distDir's src-root-relative path.
    scriptFull = "(cd ${frontendRoot} && ${tauriConf.build.beforeBuildCommand})";
    distDir = "${tauriRoot}/${tauriConf.build.frontendDist}";
  }
