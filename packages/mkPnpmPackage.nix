{
  pnpm2nix,
  stdenv,
  fullCleanSource,
  ...
}:
{ src, ... }@attrs:
pnpm2nix.packages.${stdenv.hostPlatform.system}.mkPnpmPackage attrs
// {
  src = fullCleanSource src;
}
