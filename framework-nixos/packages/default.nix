self: super:
{
  adi1090x-plymouth = super.callPackage ./adi1090x-plymouth { };
  mailspring = import ./mailspring.nix {
    inherit (super) lib fetchurl;
    base = super.mailspring;
    tidy = super.html-tidy;
  };
}
