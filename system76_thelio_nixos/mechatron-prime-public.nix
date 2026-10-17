# Public CI surface for this machine. Funnel, tailnet port 80, the badge
# MIME map, and the service worker that drops Collie's old claim on port 443
# are host configuration. They belong in this flake so a reboot applies them.
# The private Mac builder key stays a root-only file outside the store.
{ pkgs, lib, ... }:
let
  publicDirectory = "/var/lib/mechatron-prime-public";
  ts = "${pkgs.tailscale}/bin/tailscale";
  routes = pkgs.writeShellScript "mechatron-prime-public-routes" ''
    set -u
    ${ts} funnel --bg --yes --set-path=/hooks/github http://127.0.0.1:9000/hooks/github
    ${ts} funnel --bg --yes --set-path=/badges http://127.0.0.1:9001/badges
    ${ts} funnel --bg --yes --set-path=/mechatron-prime http://127.0.0.1:9001/mechatron-prime
    ${ts} funnel --bg --yes --set-path=/sw.js http://127.0.0.1:9001/sw.js
    ${ts} serve --bg --yes --http=80 --set-path=/badges http://127.0.0.1:9001/badges
    ${ts} serve --bg --yes --http=80 --set-path=/hooks/github http://127.0.0.1:9000/hooks/github
    ${ts} serve --bg --yes --http=80 --set-path=/mechatron-prime http://127.0.0.1:9001/mechatron-prime
    ${ts} serve --bg --yes --http=80 --set-path=/sw.js http://127.0.0.1:9001/sw.js
  '';
in
{
  # The vendored badge unit predates the JPEG XL map. This replaces only its
  # command. JSON stays the default for unknown types.
  systemd.services.mechatron-prime-badges.serviceConfig.ExecStart = lib.mkForce "${pkgs.darkhttpd}/bin/darkhttpd ${publicDirectory} --addr 127.0.0.1 --port 9001 --no-listing --hide-dotfiles --mimetypes ${./mechatron-public-mimetypes} --default-mimetype application/json --no-server-id";

  systemd.tmpfiles.rules = [
    "L+ ${publicDirectory}/sw.js - - - - ${./mechatron-unregister-service-worker.js}"
  ];

  systemd.services.mechatron-prime-public-routes = {
    description = "Publish Mechatron CI paths on Funnel 443 and tailnet port 80";
    wantedBy = [ "multi-user.target" ];
    after = [
      "tailscaled.service"
      "mechatron-prime-badges.service"
      "mechatron-prime-webhook.service"
    ];
    wants = [
      "tailscaled.service"
      "mechatron-prime-badges.service"
      "mechatron-prime-webhook.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = routes;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # These files were imperative bridges for the same behavior. Once this
  # generation is the booted system they would override it, so activation
  # removes them. The builder key under /etc/mechatron-prime/mac-builder stays.
  system.activationScripts.mechatronImperativeBridges.text = ''
    rm -f \
      /usr/local/lib/systemd/system-generators/mechatron-darwin-builder \
      /usr/local/lib/systemd/system-generators/mechatron-dune-firewall \
      /usr/local/lib/systemd/system-generators/mechatron-badge-mimetype \
      /usr/local/lib/mechatron/dune-firewall
  '';
}
