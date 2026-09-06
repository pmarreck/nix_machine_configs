#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if command -v python3 >/dev/null; then
  python3 "$root/tests/ups_formats_test.py" "$root/system76_thelio_nixos/ups/status-format.jq"
else
  nix shell --inputs-from "$root" nixpkgs#python3 --command \
    python3 "$root/tests/ups_formats_test.py" "$root/system76_thelio_nixos/ups/status-format.jq"
fi
