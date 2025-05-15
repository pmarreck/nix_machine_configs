{ stdenv, fetchFromGitHub, cmake, ninja, luajit, pkg-config, lib }:

stdenv.mkDerivation rec {
  pname = "yuescript";
  version = "0.27.5";

  src = fetchFromGitHub {
    owner = "IppClub";
    repo = "YueScript";
    rev = "v0.27.5";
    hash = "sha256-s8cHTi+aSpramXpJ8Y0/9MGDk79kDlKRIYKqIABu8VA=";
  };

  nativeBuildInputs = [ cmake ninja pkg-config ];

  LUA = "${luajit}/bin/luajit";

  preConfigure = ''
    sed -i '1iset(LUA $ENV{LUA})' CMakeLists.txt
  '';

  buildInputs = [ luajit ];

  cmakeFlags = [
    "-DLUAJIT_BIN=${luajit}/bin/luajit"
    "-DLUA_INCDIR=${luajit}/include/luajit-2.1"
    "-DLUA_LIBRARIES=${luajit}/lib/libluajit-5.1.so"
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp yue $out/bin/
  '';

  meta = with lib; {
    description = "A Moonscript-inspired language that compiles to Lua (C/C++ implementation)";
    homepage = "https://yuescript.org/";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.all;
  };
}
