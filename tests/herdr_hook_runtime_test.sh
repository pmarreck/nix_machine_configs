#!/usr/bin/env bash
# No ambient Python: the runtime must carry and exercise its own dependency.
set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$HOME/dotfiles/bin/src/capture.bash"
out="" err="" rc=0
capture nix build "$ROOT_DIR#checks.x86_64-linux.herdr-hook-runtime" --no-link
if [ "$rc" -ne 0 ]; then
	printf 'FAIL: scoped hook runtime socket/closure checks\n%s\n' "$err" >&2
	exit 1
fi
printf 'PASS: scoped hook runtime socket/closure checks\n'
