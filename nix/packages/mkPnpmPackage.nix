{
  pnpm2nix,
  stdenv,
  fullCleanSource,
  pnpm,
  ...
}: {src, ...} @ attrs:
# pnpm2nix's own `mkPnpmPackage` defaults `pnpm` to `nodejs.pkgs.pnpm`, a
# per-nodejs-version passthru nixpkgs has since dropped — pass nixpkgs'
# plain top-level `pnpm` package explicitly instead of relying on that
# default, unless the caller already supplied its own.
pnpm2nix.packages.${stdenv.hostPlatform.system}.mkPnpmPackage (
  {inherit pnpm;} // attrs
)
// {
  src = fullCleanSource src {};
}
