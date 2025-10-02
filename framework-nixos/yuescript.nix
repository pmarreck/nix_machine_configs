{ stdenv, fetchFromGitHub, cmake, ninja, luajit, pkg-config, lib }:

stdenv.mkDerivation rec {
  pname = "yuescript";
  version = "0.29.4";

  src = fetchFromGitHub {
    owner = "IppClub";
    repo = "YueScript";
    rev = "v${version}";
    sha256 = "sha256-wbrqmsZbvgEHdvJ9QKBcSX2GBKBlqRWezoXNHTDdF6M=";
  };

  nativeBuildInputs = [ cmake ninja pkg-config ];

  LUA = "${luajit}/bin/luajit";

  preConfigure = ''
    sed -i '1iset(LUA $ENV{LUA})' CMakeLists.txt
  '';

  buildInputs = [ luajit ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DLUAJIT_BIN=${LUA}"
    "-DLUA_INCDIR=${luajit}/include/luajit-2.1"
    "-DLUA_LIBRARIES=${luajit}/lib/libluajit-5.1.so"
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp yue $out/bin/
    runHook postInstall
  '';

  meta = with lib; {
    description = "A Moonscript-inspired language that compiles to Lua (C/C++ implementation)";
    homepage = "https://yuescript.org/";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.all;
  };
}
