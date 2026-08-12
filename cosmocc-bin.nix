# cosmocc: Justine Tunney's official prebuilt Cosmopolitan toolchain,
# fetched directly from https://cosmo.zip — shared by ALL hosts.
#
# Why not nixpkgs' `cosmocc`? Two reasons, each sufficient on its own:
#
#   1. STALE: nixpkgs builds cosmopolitan 2.2 from source (both release-26.05
#      and nixos-unstable as of 2026-08), while upstream releases are at 4.x.
#      We were already downloading current cosmocc manually from cosmo.zip
#      anyway; this derivation just makes that reproducible.
#
#   2. UNBUILDABLE ON ZFS: the nixpkgs source build runs cosmopolitan's test
#      suite (doCheck = true), and two of its tests hard-code the ext4-ish
#      assumption st_blocks == size/512 (test/libc/calls/ftruncate_test.c:95
#      and test/tool/net/lunix_test.lua:131). ZFS with compression=on reports
#      *actual* allocated blocks (framework got 2, thelio got 1 — for the same
#      nominal 8!), so the build fails deterministically — and since
#      cosmopolitan is 404 on cache.nixos.org it always builds locally.
#      Framework and thelio each independently hit and patched this
#      (2026-07-27 inline probe overlay on thelio, 2026-08-12 test-removal
#      overlay on framework) before converging here: a prebuilt fetch makes
#      the entire failure class inexpressible — no compile, no test suite,
#      no filesystem sensitivity.
#
# History: derivation authored for tiki-wsl-nixos (as tiki-wsl-nixos/
# cosmocc.nix), promoted to repo root 2026-08-12 for framework + thelio +
# tiki. The substituteInPlace below is load-bearing for systemPackages use
# on every host, not just WSL. APE execution verified natively on
# framework-nixos 2026-08-12 ("cosmocc (GCC) 14.1.0").
#
# To bump: check https://cosmo.zip/pub/cosmocc/ for the newest version,
# update `version`, set hash = "" (or lib.fakeHash), build, copy the real
# hash from the error message.
{
  coreutils,
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cosmocc";
  version = "4.0.2";

  src = fetchurl {
    url = "https://cosmo.zip/pub/cosmocc/cosmocc-${finalAttrs.version}.zip";
    hash = "sha256-hbjDekBthi5latTsFL6fbOR0wbQ2uWFekaVSCKztP0Q=";
  };

  nativeBuildInputs = [ unzip ];

  dontUnpack = true;
  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    unzip "$src" -d "$out"

    # environment.systemPackages exposes only selected package directories, so
    # resolve the real script location before cosmocc constructs include and
    # library paths relative to its bin directory. (bin/cosmoc++ is a symlink
    # to bin/cosmocc, so this one substitution covers both personalities —
    # PROG=''${0##*/} still sees the invoked name through the symlink.)
    substituteInPlace "$out/bin/cosmocc" \
      --replace-fail 'BIN=''${0%/*}' \
        'BIN=$(dirname "$(${coreutils}/bin/readlink -f "$0")")'

    # WSL's generic MZ binfmt handler captures APE executables as Windows PE.
    # Assimilate the bundled host tools to native ELF in place; their paths and
    # basenames must remain unchanged because GCC uses both to select programs
    # and locate its companion resources. Compiler output remains portable APE.
    # (Harmless and still correct on non-WSL hosts: `sh tool --assimilate`
    # exploits the APE shell-script polyglot, needing no binfmt at all.)
    find "$out" -type f -perm -0100 -print0 > "$TMPDIR/ape-tools"
    while IFS= read -r -d "" tool; do
      if [ "$(head -c 6 "$tool")" = "MZqFpD" ]; then
        sh "$tool" --assimilate
        test "$(head -c 4 "$tool")" = "$(printf '\177ELF')"
      fi
    done < "$TMPDIR/ape-tools"

    ln -s ape-x86_64.elf "$out/bin/ape"
    runHook postInstall
  '';

  meta = {
    description = "Build-once run-anywhere C and C++ toolchain";
    homepage = "https://cosmo.zip/";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    license = with lib.licenses; [
      asl20
      gpl2Only
      gpl3Only
      isc
      lgpl2Only
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "cosmocc";
  };
})
