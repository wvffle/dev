{
  mkPnpmPackage,
  fullCleanSource,
  lib,
  ...
}: {
  src,
  tauriRoot ? "src-tauri",
  tauriConf ? builtins.fromJSON (builtins.readFile "${src}/${tauriRoot}/tauri.conf.json"),
}: let
  rootCargoTomlPath = "${src}/Cargo.toml";
  workspaceMembers =
    if builtins.pathExists rootCargoTomlPath
    then (builtins.fromTOML (builtins.readFile rootCargoTomlPath)).workspace.members or []
    else [];

  rustCrateDirs = lib.unique ([tauriRoot] ++ workspaceMembers);

  relOf = path: lib.removePrefix (toString src + "/") (toString path);
  isUnderCrateDir = rel: crateDir: rel == crateDir || lib.hasPrefix "${crateDir}/" rel;
in
  mkPnpmPackage {
    pname = "${tauriConf.productName}-frontend";
    version = tauriConf.version;

    src = fullCleanSource src {
      allow = [
        # tauri.conf.json itself, plus tauriRoot as a bare directory so
        # cleanSourceWith can traverse into it to reach that file - without
        # this, tauriRoot gets excluded by the crate-dir deny rule below
        # before the filter ever gets to visit the file inside it.
        (path: type: relOf path == "${tauriRoot}/tauri.conf.json")
        (path: type: relOf path == tauriRoot)
      ];
      deny = [
        # Rust crate directories (tauriRoot's own rust sources, and any
        # other workspace member crates) don't belong in the frontend
        # build - excluding them keeps a Rust-only change from busting the
        # frontend build cache.
        (path: type: lib.any (isUnderCrateDir (relOf path)) rustCrateDirs)
        (path: type: relOf path == "target" || lib.hasPrefix "target/" (relOf path))
      ];
    };

    scriptFull = tauriConf.build.beforeBuildCommand;
    distDir = "${tauriRoot}/${tauriConf.build.frontendDist}";
  }
