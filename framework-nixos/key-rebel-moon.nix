{ lib, fetchzip }:

let
  version = "2.0";
in fetchzip rec {

  name = "key-rebel-moon-${version}";

  url = "https://github.com/pmarreck/dotfiles/raw/cb5500c96722699a0cc7e0793a08f9b25236cb97/bin/data/key-rebel-moon.zip";

  postFetch = ''
    downloadedFile="/build/key-rebel-moon.zip"
    # echo "downloadedFile=$downloadedFile"
    # echo "out=$out"
    mkdir -p $out/share/fonts
    unzip -j $downloadedFile \*.otf -d $out/share/fonts/opentype
  '';

  sha256 = "sha256-29nLsGSKif4TSrH9RDQZOkAgIMEVoDOAPRvFlxdQ/JI=";

  meta = with lib; {
    homepage = "";
    description = "A typeface specially designed for coding";
    license = licenses.ofl;
    platforms = platforms.all;
    maintainers = with maintainers; [ pmarreck ];
  };
}
