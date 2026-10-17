#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
filter="$root/system76_thelio_nixos/ups/status.jq"
render() { jq -nS --arg nut "$1" --arg monitor "$2" --argjson nut_ok "${3:-true}" -f "$filter"; }
fixture=$'battery.charge: 100\ndriver.version: 2.8.4\ndriver.version.data: HID: revision 4\nups.serial: 00123\nups.status: OL'
output=$(render "$fixture" '{"shutdown_enabled":false,"outage_elapsed_seconds":42}')
jq -e '.nut.battery.charge == "100" and .nut.driver.version._value == "2.8.4" and
 .nut.driver.version.data == "HID: revision 4" and .nut.ups.serial == "00123" and
 .monitor.shutdown_enabled == false and .monitor.outage_elapsed_seconds == 42 and
 .errors == []' <<<"$output" >/dev/null
# Prefix collisions must preserve both values, regardless of input order.
render $'a.b.c: leaf\na.b: parent\na: root' '{}' |
 jq -e '.nut.a._value == "root" and .nut.a.b._value == "parent" and .nut.a.b.c == "leaf"' >/dev/null
for bad in 'not a record' $'x: first\nx: second' 'x..y: bad' 'x._value: reserved'; do
 render "$bad" '{}' | jq -e '.nut == null and (.errors | length) == 1' >/dev/null
done
render 'ups.status: OB' '{}' false | jq -e '.nut == null and (.errors | length) == 1' >/dev/null
for bad in '' 'not json' '[]' 'null'; do
 render 'ups.status: OL' "$bad" | jq -e '.nut.ups.status == "OL" and .monitor == null and (.errors | length) == 1' >/dev/null
done
render $'device.model: "UPS" \\ backup\r\nempty.value: \r\n' '{}' |
 jq -e '.nut.device.model == "\"UPS\" \\ backup" and .nut.empty.value == ""' >/dev/null
render '' '{}' | jq -e '.nut == null and (.errors | length) == 1' >/dev/null
printf '13 UPS JSON formatting/error scenarios passed\n'
if output=$(bash "$root/system76_thelio_nixos/ups/status.sh" \
  "$(type -P false)" "$(type -P jq)" "$(type -P timeout)" "$filter" "$root/system76_thelio_nixos/ups/status-format.jq" /nonexistent/ups-status.json); then
  printf 'failed sources must produce a nonzero exit status\n' >&2; exit 1
fi
jq -e '.nut == null and .monitor == null and (.errors | length) == 2' <<<"$output" >/dev/null
printf 'UPS CLI failed-source JSON and exit-status check passed\n'
cli() {
 bash "$root/system76_thelio_nixos/ups/status.sh" "$(type -P false)" "$(type -P jq)" \
   "$(type -P timeout)" "$filter" "$root/system76_thelio_nixos/ups/status-format.jq" \
   /nonexistent/ups-status.json "$@"
}
for modifier in export declaration; do
 if [ "$modifier" = export ]; then format=--bash; prefix='export UPS_STATUS_'; else format=--xml; prefix='<?xml '; fi
 if output=$(cli "$format" "--$modifier"); then rc=0; else rc=$?; fi
 [ "$rc" -eq 1 ] # unavailable source, NOT a usage error
 [[ "$output" == "$prefix"* ]]
 if output=$(cli "--$modifier" "$format" 2>&1); then rc=0; else rc=$?; fi
 [ "$rc" -eq 2 ]
done
if output=$(cli --bash); then rc=0; else rc=$?; fi
[ "$rc" -eq 1 ]
[ "${output#UPS_STATUS_}" != "$output" ]
for format in --json --toml --xml; do
 if output=$(cli "$format" --export 2>&1); then rc=0; else rc=$?; fi
 [ "$rc" -eq 2 ]
 [ "$output" = 'ups-status: --export requires preceding --bash' ]
done
if output=$(cli --xml); then rc=0; else rc=$?; fi
[ "$rc" -eq 1 ]
[[ "$output" == '<ups-status '* ]]
for args in '--json --declaration' '--xml --declaration --json' '--bash --export --xml' '--null-value=:null --toml' '--toml --null-value' '--toml --null-value=:null --json'; do
 read -ra argv <<<"$args"
 if output=$(cli "${argv[@]}" 2>&1); then rc=0; else rc=$?; fi
 [ "$rc" -eq 2 ]
done
for syntax in equal separate; do
 if [ "$syntax" = equal ]; then args=(--null-value=:null); else args=(--null-value :null); fi
 if output=$(cli --toml "${args[@]}"); then rc=0; else rc=$?; fi
 [ "$rc" -eq 1 ]
 [[ "$output" == *'nut = ":null"'* ]]
 [[ "$output" == *'monitor = ":null"'* ]]
done
if output=$(cli --toml --null-value=); then rc=0; else rc=$?; fi
[ "$rc" -eq 1 ]
[[ "$output" == *'nut = ""'* ]]
printf 'UPS CLI format modifiers, strict option ordering, null sentinel syntax and invalid-combination checks passed\n'
