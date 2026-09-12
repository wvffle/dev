# Vendored (with the cargo-miri wrapper rebuilt as a `writeShellScriptBin`
# instead of a substituted-in-place .sh file — dead code either way here,
# since selectedComponents in ./rust-xtensa.nix never includes
# cargo-miri) from
# https://github.com/milas/esp-flake/blob/main/pkgs/rust/mk-aggregated.nix
# (itself adapted from nixpkgs' internal rust-bin component installer),
# MIT-licensed — see ./rust-xtensa.nix for why this is vendored rather
# than taken as a flake input.
{
  lib,
  stdenv,
  symlinkJoin,
  pkgsTargetTarget,
  writeShellScriptBin,
}: {
  pname,
  version,
  date,
  selectedComponents,
  availableComponents ? selectedComponents,
}: let
  inherit (lib) optional;
  inherit (stdenv) targetPlatform;

  # Resolves rust-src relative to its own runtime location (via $0) rather
  # than a Nix-eval-time $out, since this wrapper is copied into the
  # aggregated toolchain's $out *after* this derivation already exists.
  cargoMiriWrapper = writeShellScriptBin "cargo-miri" ''
    self_dir="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
    src_dir="$self_dir/lib/rustlib/src/rust/library"
    if [[ ! -v XARGO_RUST_SRC ]]; then
      if [[ ! -d "$src_dir" ]]; then
        echo '`rust-src` is required by miri but not installed.' >&2
        echo 'Please either install component `rust-src` or set `XARGO_RUST_SRC`.' >&2
        exit 1
      fi
      export XARGO_RUST_SRC="$src_dir"
    fi
    exec -a "$0" "$self_dir/bin/.cargo-miri-wrapped" "$@"
  '';
in
  symlinkJoin {
    name = pname + "-" + version;
    inherit pname version;

    paths = selectedComponents;

    passthru = {inherit availableComponents;};

    # Ourselves have offset -1. In order to make these offset -1 dependencies of downstream derivation,
    # they are offset 0 propagated.

    # CC for build script linking.
    # Workaround: should be `pkgsHostHost.cc` but `stdenv`'s cc itself have -1 offset.
    depsHostHostPropagated = [stdenv.cc];

    # CC for crate linking.
    # Workaround: should be `pkgsHostTarget.cc` but `stdenv`'s cc itself have -1 offset.
    # N.B. WASM targets don't need our CC.
    propagatedBuildInputs =
      optional (!targetPlatform.isWasm) pkgsTargetTarget.stdenv.cc;

    # Link dependency for target, required by darwin std.
    depsTargetTargetPropagated =
      optional (targetPlatform.isDarwin) [pkgsTargetTarget.libiconv];

    # If rustc or rustdoc is in the derivation, we need to copy their
    # executable into the final derivation. This is required
    # for making them find the correct SYSROOT.
    postBuild =
      ''
        for file in $out/bin/{rustc,rustdoc,miri,cargo-miri}; do
          if [ -e $file ]; then
            cp --remove-destination "$(realpath -e $file)" $file
          fi
        done
      ''
      # Workaround: https://github.com/rust-lang/rust/pull/103660
      # FIXME: This duplicates the space usage since `librustc_driver` is huge.
      + lib.optionalString (date == null || date >= "2022-11-01") ''
        for file in $out/bin/{rustc,rustdoc,miri,cargo-miri,cargo-clippy,clippy-driver}; do
          if [ -e $file ]; then
            [[ $file != */*clippy* ]] || cp --remove-destination "$(realpath -e $file)" $file
            chmod +w $file
            ${lib.optionalString stdenv.isLinux ''
          patchelf --set-rpath $out/lib "$file" || true
        ''}
            ${lib.optionalString stdenv.isDarwin ''
          install_name_tool -add_rpath $out/lib "$file" || true
        ''}
          fi
        done
        shopt nullglob
        for file in $out/lib/librustc_driver*; do
          cp --remove-destination "$(realpath -e $file)" $file
        done
      ''
      + ''
        if [ -e $out/bin/cargo-miri ]; then
          mv $out/bin/{cargo-miri,.cargo-miri-wrapped}
          cp ${cargoMiriWrapper}/bin/cargo-miri $out/bin/cargo-miri
          chmod +w $out/bin/cargo-miri
        fi

        # symlinkJoin doesn't automatically handle it. Thus do it manually.
        mkdir $out/nix-support
        echo "$depsHostHostPropagated " >$out/nix-support/propagated-host-host-deps
        [[ -z "$propagatedBuildInputs" ]] || echo "$propagatedBuildInputs " >$out/nix-support/propagated-build-inputs
        [[ -z "$depsTargetTargetPropagated" ]] || echo "$depsTargetTargetPropagated " >$out/nix-support/propagated-target-target-deps
      '';

    meta.platforms = lib.platforms.all;
  }
