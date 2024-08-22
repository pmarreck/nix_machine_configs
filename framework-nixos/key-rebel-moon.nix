{ lib, fetchzip }:

let
  version = "1.1";
in fetchzip rec {

  name = "key-rebel-moon-${version}";

  url = "https://github.com/pmarreck/dotfiles/raw/0fce7d330beff005f75336fac2aeb75cbceb1691/bin/key-rebel-moon.zip";

  postFetch = ''
    downloadedFile="/build/key-rebel-moon.zip"
    # echo "downloadedFile=$downloadedFile"
    # echo "out=$out"
    mkdir -p $out/share/fonts
    unzip -j $downloadedFile \*.otf -d $out/share/fonts/opentype
  '';

  sha256 = "sha256-xU/NQmTkZdFpmfhlXW8iXapegtQ+hez3mFL78vpcSxg=";

  meta = with lib; {
    homepage = "";
    description = "A typeface specially designed for coding";
    license = licenses.ofl;
    platforms = platforms.all;
    maintainers = with maintainers; [ pmarreck ];
  };
}

