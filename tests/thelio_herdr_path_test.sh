#!/usr/bin/env bash

# Effective Herdr service contract. Agent discovery happens inside the
# supervised user service, so its evaluated PATH must include Peter's stable
# launcher directories without evaluating interactive shell startup.

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
capture nix eval --raw \
	"path:$ROOT_DIR#nixosConfigurations.thelio-nixos.config.systemd.user.services.herdr.environment.PATH"

if [ "$rc" -eq 0 ]; then
	pass 'effective Herdr PATH evaluates'
else
	fail "effective Herdr PATH must evaluate (exit $rc)"
fi

case ":$out:" in
	*:/home/pmarreck/.local/bin:*) pass 'Herdr discovers user-local agent launchers' ;;
	*) fail 'Herdr PATH must include /home/pmarreck/.local/bin' ;;
esac

case ":$out:" in
	*:/home/pmarreck/.grok/bin:*) pass 'Herdr discovers the vendor-managed Grok launcher' ;;
	*) fail 'Herdr PATH must include /home/pmarreck/.grok/bin' ;;
esac

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
