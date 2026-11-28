#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# A python3 on PATH can be a stub that refuses to run; fall back to Nix's Python then.
if python3 -c "" >/dev/null 2>&1; then
  python3 "$root/tests/ups_formats_test.py" "$root/system76_thelio_nixos/ups/status-format.jq"
else
  nix shell --inputs-from "$root" nixpkgs#python3 --command \
    python3 "$root/tests/ups_formats_test.py" "$root/system76_thelio_nixos/ups/status-format.jq"
fi
