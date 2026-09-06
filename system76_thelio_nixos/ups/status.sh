#!/usr/bin/env bash
# Dependencies and state path are explicit arguments from the Nix wrapper.
set -eu
upsc="$1"; jq="$2"; timeout="$3"; filter="$4"; renderer="$5"; state="$6"
shift 6
format=json
export_vars=false
declaration=false
null_value=''
null_value_set=false
usage='Usage: ups-status [--json | --toml [--null-value VALUE] | --xml [--declaration] | --bash [--export]]'
fail() { printf 'ups-status: %s\n' "$1" >&2; exit 2; }
while [ "$#" -gt 0 ]; do
  option="$1"
  shift
  case "$option" in
    --json|--toml|--xml|--bash) format="${option#--}" ;;
    --export)
      [ "$format" = bash ] || fail '--export requires preceding --bash'
      export_vars=true ;;
    --declaration)
      [ "$format" = xml ] || fail '--declaration requires preceding --xml'
      declaration=true ;;
    --null-value|--null-value=*)
      [ "$format" = toml ] || fail '--null-value requires preceding --toml'
      if [ "$option" = --null-value ]; then
        [ "$#" -gt 0 ] || fail '--null-value requires a value (use --null-value= for an empty string)'
        null_value="$1"; shift
      else
        null_value="${option#--null-value=}"
      fi
      null_value_set=true ;;
    --help|-h) printf '%s\n' "$usage"; exit 0 ;;
    *) printf '%s\n' "$usage" >&2; exit 2 ;;
  esac
done
if [ "$export_vars" = true ] && [ "$format" != bash ]; then
  fail '--export requires final Bash output'
fi
if [ "$declaration" = true ] && [ "$format" != xml ]; then
  fail '--declaration requires final XML output'
fi
if [ "$null_value_set" = true ] && [ "$format" != toml ]; then
  fail '--null-value requires final TOML output'
fi
nut_ok=true
if ! nut_text=$("$timeout" 5 "$upsc" everamp@127.0.0.1); then
  nut_ok=false
fi
monitor_text=''
if [ -r "$state" ]; then monitor_text=$(<"$state"); fi
output=$("$jq" -nS --arg nut "$nut_text" --argjson nut_ok "$nut_ok" \
  --arg monitor "$monitor_text" -f "$filter")
"$jq" -rS --arg format "$format" --argjson export_vars "$export_vars" \
  --argjson declaration "$declaration" --argjson null_value_set "$null_value_set" \
  --arg null_value "$null_value" -f "$renderer" <<<"$output"
# Preserve useful partial JSON while signaling unavailable/malformed sources.
"$jq" -e '.errors | length == 0' <<<"$output" >/dev/null
