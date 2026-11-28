#!/usr/bin/env bash

# Tiki rebuilds from a home-directory checkout, and its /etc/nixos stays nearly
# empty on purpose, so the dotfiles repo-awareness hook cannot discover that
# checkout itself. Its configuration must name the checkout the repository
# README clones into: the default WSL user's ~/nixos-configs. It must be a
# session variable, set through PAM, so systemd user services see it as well as
# login shells.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

contract="$({
	nix eval --json "$ROOT_DIR#nixosConfigurations.tiki-wsl-nixos.config" --apply '
		config: {
			named = config.environment.sessionVariables.REPO_AWARENESS_HOST_REPOS or null;
			expected = config.users.users.${config.wsl.defaultUser}.home + "/nixos-configs";
		}
	' 2>/dev/null
})"
status=$?

if [ "$status" -eq 0 ]; then
	pass 'Tiki host-repository contract evaluates'
else
	fail 'Tiki host-repository contract must evaluate'
fi

if [ -n "$contract" ] && jq -e '.named != null and .named == .expected' <<<"$contract" >/dev/null; then
	pass "Tiki names its configuration checkout for repo-awareness ($(jq -r .named <<<"$contract"))"
else
	fail "REPO_AWARENESS_HOST_REPOS must be the default user's ~/nixos-configs, got [$contract]"
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
