#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
luajit "$root/tests/ups_policy_test.lua" "$root/system76_thelio_nixos/ups/policy.lua"
luajit "$root/tests/ups_runtime_test.lua" "$root/system76_thelio_nixos/ups/monitor.lua" "$root/system76_thelio_nixos/ups/policy.lua"
