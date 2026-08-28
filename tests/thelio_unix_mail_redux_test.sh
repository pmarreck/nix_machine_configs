#!/usr/bin/env bash

# Effective Thelio contract for tailnet-local human/agent mail.

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
	"path:$ROOT_DIR#nixosConfigurations.thelio-nixos.config.services.unix-mail-redux"

if [ "$rc" -eq 0 ]; then
	pass 'effective UNIX MAIL REDUX configuration evaluates'
else
	fail "effective UNIX MAIL REDUX configuration must evaluate (exit $rc)"
fi

assert_json() {
	local query=$1
	local expected=$2
	local label=$3
	local actual
	actual="$(jq -r "$query" <<< "$out" 2>/dev/null)"
	[ "$actual" = "$expected" ] && pass "$label" || fail "$label: expected [$expected], got [$actual]"
}

assert_json '.enable' 'true' 'tailnet mail is enabled'
assert_json '.owner' 'pmarreck' 'mailbox belongs to Peter'
assert_json '.humanLocalPart' 'peter' 'human inbox has the stable peter address'
assert_json '.domain' 'agents.home.arpa' 'mail remains in the private home.arpa namespace'
assert_json '.tailscaleDomain' 'thelio-nixos.tail66c90.ts.net' 'TLS uses the Thelio MagicDNS name'
assert_json '.enableWatcher' 'true' 'idle-agent delivery watcher is enabled'
assert_json '.wakeProjects | join(",")' '*' 'all project mailboxes are eligible for conservative idle wakeup'

capture nix eval --raw \
	"path:$ROOT_DIR#nixosConfigurations.thelio-nixos.config.services.dovecot2.package.version"

if [ "$rc" -eq 0 ] && [[ "$out" == 2.4.* ]]; then
	pass 'mail module selects Dovecot 2.4 for its 2.4 configuration syntax'
else
	fail "mail module must select Dovecot 2.4, got [$out] (exit $rc)"
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
