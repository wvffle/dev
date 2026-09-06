{
  mkPnpmPackage,
  fullCleanSource,
  lib,
  ...
}: {
  src,
  tauriRoot ? "src-tauri",
  tauriConf ? builtins.fromJSON (builtins.readFile "${src}/${tauriRoot}/tauri.conf.json"),
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
  rootCargoTomlPath = "${src}/Cargo.toml";
  workspaceMembers =
    if builtins.pathExists rootCargoTomlPath
    then (builtins.fromTOML (builtins.readFile rootCargoTomlPath)).workspace.members or []
    else [];

  rustCrateDirs = lib.unique ([tauriRoot] ++ workspaceMembers);

  relOf = path: lib.removePrefix (toString src + "/") (toString path);
  isUnderDir = rel: dir: dir == "." || rel == dir || lib.hasPrefix "${dir}/" rel;
  isUnderCrateDir = isUnderDir;

  # Root pnpm workspace manifests: always needed for pnpm2nix to resolve
  # the workspace at all, regardless of frontendRoot.
  pnpmWorkspaceManifests = ["package.json" "pnpm-lock.yaml" "pnpm-workspace.yaml"];

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
    || lib.elem rel pnpmWorkspaceManifests
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

    scriptFull = tauriConf.build.beforeBuildCommand;
    distDir = "${tauriRoot}/${tauriConf.build.frontendDist}";
  }
