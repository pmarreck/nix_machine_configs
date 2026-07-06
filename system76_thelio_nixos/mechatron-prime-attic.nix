# Mechatron Prime — tailnet-local Attic binary cache.
#
# This is the cache half of the Garnix replacement. The webhook runner will push
# successful Nix build outputs here, and Peter's machines will consume them over
# Tailscale.
#
# Secret setup, before first rebuild:
#   sudo install -d -m0750 /etc/mechatron-prime
#   sudo bash -c 'umask 0137; printf "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=" > /etc/mechatron-prime/atticd.env; openssl genrsa -traditional 4096 | base64 -w0 >> /etc/mechatron-prime/atticd.env; printf "\n" >> /etc/mechatron-prime/atticd.env'
{ pkgs, ... }:
{
  services.atticd = {
    enable = true;
    environmentFile = "/etc/mechatron-prime/atticd.env";

    settings = {
      listen = "100.96.171.61:8080";

      chunking = {
        nar-size-threshold = 65536;
        min-size = 16384;
        avg-size = 65536;
        max-size = 262144;
      };
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8080 ];

  nix.settings = {
    substituters = [ "http://100.96.171.61:8080/fleet" ];
    trusted-public-keys = [ "fleet:dgyz6SFBwdHQaS8C4NxcXD5s1uEgStJZ5i/KODzrsE8=" ];
  };

  environment.systemPackages = [
    pkgs.attic-client
  ];
}
