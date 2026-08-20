{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  luajit,
  pkg-config,
}:

stdenv.mkDerivation rec {
  pname = "yuescript";
  version = "0.29.2";

  src = fetchFromGitHub {
    owner = "IppClub";
    repo = "YueScript";
    rev = "v${version}";
    hash = "sha256-rK2gfganKcv/dITHNnK0k79mX8qVK7uMZOKeO7Vsook=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];
  buildInputs = [ luajit ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DLUA=${luajit}/bin/luajit"
    "-DLUA_INCLUDE_DIR=${luajit}/include/luajit-2.1"
    "-DLUA_LIBRARY=${luajit}/lib/libluajit-5.1.${if stdenv.hostPlatform.isDarwin then "dylib" else "so"}"
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp yue $out/bin/
    runHook postInstall
  '';

  meta = {
    description = "A Moonscript-inspired language that compiles to Lua (C/C++ implementation)";
    homepage = "https://yuescript.org/";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
