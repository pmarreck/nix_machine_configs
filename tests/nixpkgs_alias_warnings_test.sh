#!/usr/bin/env bash
# Host package lists must not name Nixpkgs aliases that warn during evaluation.
# Comments are ignored so a note can still mention the old name.
set -u
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fail=0
bad() { printf 'not ok - %s\n' "$1" >&2; fail=1; }
ok() { printf 'ok - %s\n' "$1"; }

code() {
	sed -E 's/[[:space:]]*#.*$//' "$1"
}

# A hit in a module evaluated against nixos-unstable is a warning on the next
# Thelio or Framework eval. tiki's parity list is release-26.05, where
# gemini-cli.meta.problems is empty and antigravity-cli does not exist yet.
forbidden='gemini-cli|libreoffice-fresh|libreoffice-still|extractType2'
found=0
while IFS= read -r file; do
	case "$file" in
		*/tiki-wsl-nixos/darwin-package-parity.nix) continue ;;
	esac
	if code "$file" | grep -E -q "$forbidden"; then
		printf 'not ok - %s still names a warning alias\n' "${file#"$root"/}" >&2
		code "$file" | grep -n -E "$forbidden" >&2 || true
		found=1
	fi
done < <(find "$root" -name '*.nix' -type f ! -path '*/.git/*')
if [ "$found" -eq 0 ]; then
	ok "unstable-evaluated nix files do not name gemini-cli, libreoffice-fresh, libreoffice-still, or extractType2"
else
	fail=1
fi

need() {
	file=$1
	label=$2
	pattern=$3
	if code "$file" | grep -E -q "$pattern"; then
		ok "$label"
	else
		bad "$label"
	fi
}

need "$root/system76_thelio_nixos/configuration.nix" \
	"thelio installs antigravity-cli" \
	'(^|[^[:alnum:]_-])antigravity-cli([^[:alnum:]_-]|$)'
need "$root/framework-nixos/configuration.nix" \
	"framework installs antigravity-cli" \
	'(^|[^[:alnum:]_-])antigravity-cli([^[:alnum:]_-]|$)'
need "$root/system76_thelio_nixos/configuration.nix" \
	"thelio installs libreoffice" \
	'(^|[^[:alnum:]_-])libreoffice([^[:alnum:]_-]|$)'
need "$root/framework-nixos/configuration.nix" \
	"framework installs libreoffice" \
	'(^|[^[:alnum:]_-])libreoffice([^[:alnum:]_-]|$)'
need "$root/packages/tmog.nix" \
	"tmog extracts the AppImage with appimageTools.extract" \
	'appimageTools\.extract[[:space:]]*\{'

[ "$fail" -eq 0 ]
