{ lib
, stdenv
, fetchFromGitHub
, cmake
, pkg-config
, ncurses
, libbsd
}:

stdenv.mkDerivation rec {
  pname = "cfunge";
  version = "unstable-29e4cfa";

  src = fetchFromGitHub {
    owner = "VorpalBlade";
    repo = "cfunge";
    rev = "29e4cfa1cc1f4553bf0e2908f819e913c32dfda8";
    hash = "sha256-Vb1Cg4h+uDk4I8XFnTnoS1LsHQVH1xg58wDpEeZF/R8=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs =
    [
      ncurses
      libbsd
    ];

  cmakeBuildType = "Release";
  enableParallelBuilding = true;

  meta = with lib; {
    description = "Fast Befunge93/98/109 interpreter in C";
    homepage = "https://github.com/VorpalBlade/cfunge";
    license = licenses.gpl3Plus;
    mainProgram = "cfunge";
    platforms = platforms.unix;
  };
}
