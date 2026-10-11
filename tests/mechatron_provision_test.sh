#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$HOME/dotfiles/bin/src/capture.bash"
out="" err="" rc=0
capture nix eval --json "$root#nixosConfigurations.thelio-nixos.config.systemd.services.mechatron-prime-provision.serviceConfig"
if [ "$rc" -ne 0 ]; then printf 'FAIL: provisioning service evaluation\n' >&2; exit 1; fi
if ! jq -e '.DynamicUser == true and .User == "mechatron-prime-provision" and .ProtectHome == true and .ProtectSystem == "strict" and .NoNewPrivileges == true and .KillMode == "control-group" and (.LoadCredential | length) == 2' <<< "$out" >/dev/null; then
	printf 'FAIL: provisioning service isolation\n' >&2; exit 1
fi
capture nix eval --json "$root#nixosConfigurations.thelio-nixos.config.systemd.sockets.mechatron-prime-provision.socketConfig"
if [ "$rc" -ne 0 ]; then printf 'FAIL: provisioning socket evaluation\n' >&2; exit 1; fi
if ! jq -e '.SocketMode == "0600" and .ListenStream == "/run/mechatron-prime-provision.sock"' <<< "$out" >/dev/null; then
	printf 'FAIL: provisioning socket access boundary\n' >&2; exit 1
fi
printf 'PASS: effective provisioning service and socket isolation\n'
