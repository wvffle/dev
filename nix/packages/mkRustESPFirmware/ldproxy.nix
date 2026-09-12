# The linker-proxy esp-idf-sys's build script needs for Xtensa targets
# (see ../mkRustESPFirmware.nix, its only consumer) — a plain host tool
# (not cross-compiled), so built with nixpkgs' own rustPlatform rather
# than the vendored Xtensa toolchain in ./rust-xtensa.nix.
# Built from crates.io directly rather than esp-rs/embuild's GitHub
# release binaries: those lag crates.io (latest tagged release is
# ldproxy-v0.3.2 vs. crates.io's 0.3.5) enough that the older build's
# `--ldproxy-linker` handshake is incompatible with current esp-idf-sys.
{
  rustPlatform,
  fetchCrate,
}:
rustPlatform.buildRustPackage rec {
  pname = "ldproxy";
  version = "0.3.5";
  src = fetchCrate {
    inherit pname version;
    hash = "sha256-y6qhsWW9tGsc+DEieivhkzbVjVGBvkt2xhMO+8SO+kU=";
  };
  cargoHash = "sha256-cjLhBit1ASBhHY8mZtC4bae0ylxzhcJ0U4ERnIlT5ow=";
}
