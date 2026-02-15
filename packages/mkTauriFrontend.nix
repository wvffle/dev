{
  mkPnpmPackage,
  ...
}:
{
  src,
  tauriRoot ? "src-tauri",
  tauriConf ? builtins.fromJSON (builtins.readFile "${src}/${tauriRoot}/tauri.conf.json"),
}:
mkPnpmPackage {
  pname = "${tauriConf.productName}-frontend";
  version = tauriConf.version;

  # NOTE: Source is already cleaned fully in `mkPnpmPackage.nix`.
  inherit src;

  scriptFull = tauriConf.build.beforeBuildCommand;
  distDir = "${tauriRoot}/${tauriConf.build.frontendDist}";
}
