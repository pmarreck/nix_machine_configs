#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$HOME/dotfiles/bin/src/capture.bash"
out='' err='' rc=0
capture nix eval --json "git+file://$root#nixosConfigurations.thelio-nixos.config.systemd.user.slices.agentbuilds.sliceConfig"
if [[ "$rc" -ne 0 ]]; then printf 'not ok - aggregate build slice does not evaluate\n' >&2; exit 1; fi
if ! jq -e '.MemoryHigh == "24G" and .MemoryMax == "32G" and .MemorySwapMax == "2G"' <<< "$out" >/dev/null; then
	printf 'not ok - aggregate memory envelope differs from the declared contract\n' >&2; exit 1
fi
capture nix eval --json "git+file://$root#nixosConfigurations.thelio-nixos.config.systemd.user.services.build-oom-watch.serviceConfig"
if [[ "$rc" -ne 0 ]] || ! jq -e '.Restart == "always" and (.ExecStart | endswith("/bin/build-oom-watch"))' <<< "$out" >/dev/null; then
	printf 'not ok - attributed OOM monitor is not declarative\n' >&2; exit 1
fi
printf 'build resources module: aggregate slice and restartable monitor pass\n'
