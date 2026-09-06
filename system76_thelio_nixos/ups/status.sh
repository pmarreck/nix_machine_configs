#!/usr/bin/env bash
# Dependencies and state path are explicit arguments from the Nix wrapper.
set -eu
upsc="$1"; jq="$2"; timeout="$3"; filter="$4"; renderer="$5"; state="$6"
shift 6
format=json
if [ "$#" -gt 1 ]; then
  printf 'Usage: ups-status [--json|--toml|--xml|--bash]\n' >&2
  exit 2
fi
case "${1:---json}" in
  --json|--toml|--xml|--bash) format="${1:---json}"; format="${format#--}" ;;
  --help|-h) printf 'Usage: ups-status [--json|--toml|--xml|--bash]\n'; exit 0 ;;
  *) printf 'Usage: ups-status [--json|--toml|--xml|--bash]\n' >&2; exit 2 ;;
esac
nut_ok=true
if ! nut_text=$("$timeout" 5 "$upsc" everamp@127.0.0.1); then
  nut_ok=false
fi
monitor_text=''
if [ -r "$state" ]; then monitor_text=$(<"$state"); fi
output=$("$jq" -nS --arg nut "$nut_text" --argjson nut_ok "$nut_ok" \
  --arg monitor "$monitor_text" -f "$filter")
"$jq" -rS --arg format "$format" -f "$renderer" <<<"$output"
# Preserve useful partial JSON while signaling unavailable/malformed sources.
"$jq" -e '.errors | length == 0' <<<"$output" >/dev/null
