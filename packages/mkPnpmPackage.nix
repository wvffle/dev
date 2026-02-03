{
  pnpm2nix,
  stdenv,
  fullCleanSource,
  ...
}:
{ src, ... }@args:
pnpm2nix.packages.${stdenv.hostPlatform.system}.mkPnpmPackage args
// {
  src = fullCleanSource src;
}
