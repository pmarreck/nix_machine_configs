#!/usr/bin/env bash

# Tiki's WSLg terminals (WezTerm) need an installed font that covers Unicode 16
# Symbols for Legacy Computing Supplement octants, such as U+1CDAA and U+1CD6E
# (the two halves of pinterm's ball). Without one, WezTerm reports "No installed
# fonts can produce these codepoints". This builds Tiki's fonts.packages and
# asks fontconfig about the actual font files, not package names.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

# covers_codepoints CHARSET HEX...: true when fontconfig's charset string
# (space-separated hex codepoints or ranges like "20-7e") contains every HEX.
covers_codepoints() {
	local charset="$1"; shift
	awk -v want="$*" -v cs="$charset" 'BEGIN {
		n = split(cs, ranges, " "); m = split(want, cps, " ")
		for (i = 1; i <= m; i++) {
			cp = strtonum("0x" cps[i]); hit = 0
			for (j = 1; j <= n && !hit; j++) {
				k = split(ranges[j], ends, "-")
				lo = strtonum("0x" ends[1]); hi = (k > 1) ? strtonum("0x" ends[2]) : lo
				if (cp >= lo && cp <= hi) hit = 1
			}
			if (!hit) exit 1
		}
	}'
}

drvs="$(nix eval --json "$ROOT_DIR#nixosConfigurations.tiki-wsl-nixos.config.fonts.packages" \
	--apply 'builtins.map (package: package.drvPath)' 2>/dev/null | jq -r '.[]')"
if [ -n "$drvs" ]; then
	pass "Tiki's fonts.packages evaluates"
else
	fail "Tiki's fonts.packages must evaluate"
fi

outs="$(printf '%s\n' "$drvs" | xargs -r nix-store --realise 2>/dev/null)"
covering=""
while IFS= read -r font; do
	[ -n "$font" ] || continue
	charset="$(nix shell nixpkgs#fontconfig -c fc-query --format '%{charset}\n' "$font" 2>/dev/null)"
	if covers_codepoints "$charset" 1cdaa 1cd6e 2>/dev/null; then covering="$font"; break; fi
done < <(printf '%s\n' "$outs" | xargs -r -I{} find {} -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' \) 2>/dev/null)

if [ -n "$covering" ]; then
	pass "a Tiki font covers octants U+1CDAA and U+1CD6E (${covering##*/})"
else
	fail "a Tiki font must cover octants U+1CDAA and U+1CD6E"
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
