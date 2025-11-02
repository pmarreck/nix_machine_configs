{ lib
, stdenv
, cmake
, pkg-config
, ncurses
, libbsd
}:

let
  src = builtins.fetchGit {
    url = "https://github.com/VorpalBlade/cfunge";
    ref = "master";
  };

  shortRev =
    lib.optionalString (src ? rev)
      (lib.substring 0 7 src.rev);

  version =
    if shortRev == ""
    then "unstable"
    else "unstable-${shortRev}";
in
stdenv.mkDerivation {
  pname = "cfunge";
  inherit version src;

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
