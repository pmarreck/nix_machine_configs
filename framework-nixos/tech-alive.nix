{ lib, fetchzip }:

let
  version = "1.0";
in fetchzip rec {

  name = "tech-alive-${version}";

  url = "https://github.com/pmarreck/dotfiles/raw/8ff5f5d4107cdc24c26a485a6bf4e998d61fa1f9/bin/tech-alive.zip";

  postFetch = ''
    downloadedFile="/build/tech-alive.zip"
    # echo "downloadedFile=$downloadedFile"
    # echo "out=$out"
    mkdir -p $out/share/fonts
    unzip -j $downloadedFile \*.otf -d $out/share/fonts/opentype
    unzip -j $downloadedFile \*.ttf -d $out/share/fonts/truetype
  '';

  sha256 = "sha256-RQYEN+hs8WuLagLIM+x9RP2mlM9LBHGdbuy12JXuj2Q=";

  meta = with lib; {
    homepage = "";
    description = "A legendarily legible typeface";
    license = licenses.ofl;
    platforms = platforms.all;
    maintainers = with maintainers; [ pmarreck ];
  };
}

