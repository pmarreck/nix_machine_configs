#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# Check evaluated NixOS semantics, not comments claiming the system is safe.
nix eval --json "$root#nixosConfigurations.thelio-nixos.config" --apply 'c: {
  armed = c.services.everamp-monitor.shutdownEnabled;
  upsmon = c.systemd.services.upsmon.enable;
  powerdown = c.power.ups.upsmon.settings.POWERDOWNFLAG;
  shutdownOrder = c.power.ups.ups.everamp.shutdownOrder;
  port = c.power.ups.ups.everamp.port;
  firewall = c.power.ups.openFirewall;
  listeners = map (x: x.address) c.power.ups.upsd.listen;
  driver = c.systemd.services.upsdrv.serviceConfig;
}' | jq -e '
  .armed == false and .upsmon == false and .powerdown == null and
  .shutdownOrder == -1 and .port == "auto" and .firewall == false and
  .listeners == ["127.0.0.1"] and .driver.Type == "simple" and
  .driver.Restart == "on-failure"
' >/dev/null
printf 'UPS evaluated configuration safety assertions passed\n'
