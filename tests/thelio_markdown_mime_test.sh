#!/usr/bin/env bash

# Effective Thelio contract for GNOME Markdown file associations. Evaluate the
# merged NixOS option so a later module cannot silently restore GNOME Builder.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$HOME/dotfiles/bin/src/capture.bash"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

out=""
err=""
rc=0
capture nix eval --json \
	"path:$ROOT_DIR#nixosConfigurations.thelio-nixos.config.xdg.mime.defaultApplications"

if [ "$rc" -eq 0 ]; then
	pass 'effective Thelio MIME defaults evaluate'
else
	fail "effective Thelio MIME defaults must evaluate (exit $rc)"
fi

for mime_type in text/markdown text/x-markdown; do
	application="$(jq -r --arg mime_type "$mime_type" '.[$mime_type] // ""' <<< "$out" 2>/dev/null)"
	if [ "$application" = 'dev.zed.Zed.desktop' ]; then
		pass "$mime_type opens with Zed"
	else
		fail "$mime_type must open with dev.zed.Zed.desktop, got '$application'"
	fi
done

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
