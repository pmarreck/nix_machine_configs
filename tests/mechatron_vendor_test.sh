#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$root/system76_thelio_nixos/test-mechatron-prime-integration"
