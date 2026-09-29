#!/usr/bin/env bash
# Thelio must not install Docker. Peter asked for it gone on 2026-09-25.
# Comments are ignored so a note can still mention the old name.
set -u
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail=0
bad() { printf 'not ok - %s\n' "$1" >&2; fail=1; }
ok() { printf 'ok - %s\n' "$1"; }

code() {
	sed -E 's/[[:space:]]*#.*$//' "$1"
}

thelio="$root/system76_thelio_nixos"
config="$thelio/configuration.nix"

if code "$config" | grep -E -q 'virtualisation\.docker'; then
	bad "configuration.nix still sets virtualisation.docker"
	code "$config" | grep -n -E 'virtualisation\.docker' >&2 || true
else
	ok "configuration.nix does not set virtualisation.docker"
fi

if code "$config" | grep -F -q '/home/pmarreck/.local/share/docker'; then
	bad "configuration.nix still names the rootless docker data directory"
else
	ok "configuration.nix does not name the rootless docker data directory"
fi

found=0
while IFS= read -r file; do
	if code "$file" | grep -E -q 'virtualisation\.docker|pkgs\.docker'; then
		printf 'not ok - %s still references docker\n' "${file#"$root"/}" >&2
		found=1
	fi
done < <(find "$thelio" -name '*.nix' -type f)
if [ "$found" -eq 0 ]; then
	ok "Thelio nix files do not reference virtualisation.docker or pkgs.docker"
else
	fail=1
fi

exit "$fail"
