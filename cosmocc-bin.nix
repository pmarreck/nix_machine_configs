# cosmocc: Justine Tunney's official prebuilt Cosmopolitan toolchain,
# fetched directly from https://cosmo.zip (added 2026-08-12).
#
# Why not nixpkgs' `cosmocc`? Two reasons, each sufficient on its own:
#
#   1. STALE: nixpkgs builds cosmopolitan 2.2 from source (both release-26.05
#      and nixos-unstable), while upstream releases are at 4.x. We were
#      already downloading current cosmocc manually from cosmo.zip anyway;
#      this derivation just makes that reproducible.
#
#   2. UNBUILDABLE HERE: the nixpkgs source build runs cosmopolitan's test
#      suite (doCheck = true), and two of its tests hard-code the ext4-ish
#      assumption st_blocks == size/512 (test/libc/calls/ftruncate_test.c:95
#      and test/tool/net/lunix_test.lua:131). Our hosts are ZFS-rooted with
#      compression=on, which reports *actual* allocated blocks (a 4096-byte
#      ftruncated file reports 2, not 8), so the build fails deterministically
#      — and since cosmopolitan is 404 on cache.nixos.org it always builds
#      locally. A prebuilt fetch makes that entire failure class
#      inexpressible: no compile, no test suite, no filesystem sensitivity.
#
# The zip contains APE (Actually Portable Executable) binaries; verified
# running natively on framework-nixos 2026-08-12 ("cosmocc (GCC) 14.1.0").
# Derivation shape mirrors the one proven in printable_binary/flake.nix.
#
# To bump: check https://cosmo.zip/pub/cosmocc/ for the newest version,
# update `version`, set hash = "" (or lib.fakeHash), build, copy the real
# hash from the error message.
{ stdenvNoCC, fetchzip }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cosmocc-bin";
  version = "4.0.2";

  src = fetchzip {
    url = "https://cosmo.zip/pub/cosmocc/cosmocc-${finalAttrs.version}.zip";
    hash = "sha256-6KZv7KU2rJhwfc9k6z9I6ZdfIS1KqRFLZUo8YyuD7ZY=";
    stripRoot = false;
  };

  phases = [ "installPhase" ];
  installPhase = ''
    mkdir -p $out
    cp -r $src/* $out/
  '';
})
