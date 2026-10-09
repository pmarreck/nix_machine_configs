#!/usr/bin/env bash

# Contract for the WSL host's declarative PulseAudio playback CLI.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PULSEAUDIO_ATTR="$ROOT_DIR#nixosConfigurations.tiki-wsl-nixos.pkgs.pulseaudio"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

packages="$({
	nix eval --json \
		"$ROOT_DIR#nixosConfigurations.tiki-wsl-nixos.config.environment.systemPackages" \
		--apply 'builtins.map (package: package.pname or package.name or "")' 2>/dev/null
})"
eval_status=$?

if [ "$eval_status" -eq 0 ] &&
	jq -e 'index("pulseaudio") != null' <<<"$packages" >/dev/null; then
	pass 'the WSL host installs PulseAudio declaratively as a system package'
else
	fail 'the WSL host must install the PulseAudio package that provides paplay'
fi

nix build --no-link "$PULSEAUDIO_ATTR" >/dev/null 2>&1
build_status=$?
pulseaudio_path="$(nix eval --raw "$PULSEAUDIO_ATTR.outPath" 2>/dev/null)"
path_status=$?
paplay_output=""
paplay_status=1
if [ "$path_status" -eq 0 ] && [ -x "$pulseaudio_path/bin/paplay" ]; then
	paplay_output="$("$pulseaudio_path/bin/paplay" --version 2>&1)"
	paplay_status=$?
fi

if [ "$build_status" -eq 0 ] &&
	[ "$path_status" -eq 0 ] &&
	[ "$paplay_status" -eq 0 ] &&
	[[ "$paplay_output" == pacat\ * ]]; then
	pass 'the locked PulseAudio package provides a working paplay executable'
else
	fail 'the locked PulseAudio package must provide an executable bin/paplay'
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
