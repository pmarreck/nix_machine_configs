#!/usr/bin/env bash
# Dependencies and state path are explicit arguments from the Nix wrapper.
set -eu
upsc="$1"; jq="$2"; timeout="$3"; filter="$4"; renderer="$5"; state="$6"
shift 6
format=json
export_vars=false
usage='Usage: ups-status [--json|--toml|--xml|--bash] [--export (with --bash)]'
for option in "$@"; do
  case "$option" in
    --json|--toml|--xml|--bash) format="${option#--}" ;;
    --export) export_vars=true ;;
    --help|-h) printf '%s\n' "$usage"; exit 0 ;;
    *) printf '%s\n' "$usage" >&2; exit 2 ;;
  esac
done
if [ "$export_vars" = true ] && [ "$format" != bash ]; then
  printf '%s\n' 'ups-status: --export requires --bash' >&2; exit 2
fi
nut_ok=true
if ! nut_text=$("$timeout" 5 "$upsc" everamp@127.0.0.1); then
  nut_ok=false
fi
monitor_text=''
if [ -r "$state" ]; then monitor_text=$(<"$state"); fi
output=$("$jq" -nS --arg nut "$nut_text" --argjson nut_ok "$nut_ok" \
  --arg monitor "$monitor_text" -f "$filter")
"$jq" -rS --arg format "$format" --argjson export_vars "$export_vars" -f "$renderer" <<<"$output"
# Preserve useful partial JSON while signaling unavailable/malformed sources.
"$jq" -e '.errors | length == 0' <<<"$output" >/dev/null
