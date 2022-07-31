{ lib, fetchzip }:

let
  version = "1.0";
in fetchzip rec {

  name = "key-rebel-moon-${version}";

  url = "https://github.com/pmarreck/dotfiles/raw/98fda03f5a83b9dc347b605e7d9ff5aacb29ce3d/bin/key-rebel-moon.zip";

  postFetch = ''
    downloadedFile="/build/key-rebel-moon.zip"
    # echo "downloadedFile=$downloadedFile"
    # echo "out=$out"
    mkdir -p $out/share/fonts
    unzip -j $downloadedFile \*.otf -d $out/share/fonts/opentype
  '';

  sha256 = "sha256-3mvRFSuAJQwTaGjy8OvSwCGOZI3/srtrVkK9vb2hbws=";

  meta = with lib; {
    homepage = "";
    description = "A typeface specially designed for coding";
    license = licenses.ofl;
    platforms = platforms.all;
    maintainers = with maintainers; [ pmarreck ];
  };
}
