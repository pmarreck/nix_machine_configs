#!/usr/bin/env bash

set -u

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

if result="$(nix eval --raw \
	"$root_dir#nixosConfigurations.framework-nixos.config.environment.systemPackages" \
	--apply '
		packages:
		let
			cosmocc = builtins.head (builtins.filter (p: (p.pname or "") == "cosmocc") packages);
			inherit (cosmocc) version;
			expected = [
				"https://github.com/jart/cosmopolitan/releases/download/${version}/cosmocc-${version}.zip"
				"https://cosmo.zip/pub/cosmocc/cosmocc-${version}.zip"
			];
		in if cosmocc.src.urls == expected then "ok"
		else throw "unexpected cosmocc source URLs: ${builtins.toJSON cosmocc.src.urls}"
	' 2>&1)"; then
	printf 'ok - cosmocc tries the upstream release asset before cosmo.zip\n'
else
	printf 'not ok - expected the upstream release asset before cosmo.zip: %s\n' "$result" >&2
	exit 1
fi
