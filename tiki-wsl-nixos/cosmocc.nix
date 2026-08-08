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
    # library paths relative to its bin directory.
    substituteInPlace "$out/bin/cosmocc" \
      --replace-fail 'BIN=''${0%/*}' \
        'BIN=$(dirname "$(${coreutils}/bin/readlink -f "$0")")'

    # WSL's generic MZ binfmt handler captures APE executables as Windows PE.
    # Assimilate the bundled host tools to native ELF in place; their paths and
    # basenames must remain unchanged because GCC uses both to select programs
    # and locate its companion resources. Compiler output remains portable APE.
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
