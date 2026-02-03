{
  mkPnpmPackage,
  tauriConf,
  tauriRoot ? "src-tauri",
  src,
  ...
}:

mkPnpmPackage {
  pname = "${tauriConf.productName}-frontend";
  version = tauriConf.version;
  inherit src;

  scriptFull = tauriConf.build.beforeBuildCommand;
  distDir = "${tauriRoot}/${tauriConf.build.frontendDist}";
}
