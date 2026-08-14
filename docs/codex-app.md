# Official Codex app on NixOS

`packages/codex-app.nix` packages OpenAI's official x86_64 Linux `.deb` without
running its Debian maintainer scripts. The source is the immutable,
version-specific APT-pool object for `26.810.41047`, pinned by SHA-256.

The upstream payload contains Electron, native Node modules, static helpers,
glibc and musl fallbacks, optional Qt shims, and a bundled executable whose ELF
section table cannot be rewritten by `patchelf`. The package therefore runs the
unchanged payload inside a Nix-built FHS environment. The host's APT sources,
keyring, AppArmor configuration, and `/etc/default` are never touched.

## Build and verify

From this repository:

```bash
nix build .#packages.x86_64-linux.codex-app --no-link
nix build .#checks.x86_64-linux.codex-app --no-link
```

The check invokes the packaged launcher with an isolated home and requires its
reported version to equal the derivation version. It does not open a window or
modify the live Codex profile.

Run it without adding it to a system profile:

```bash
cd "$HOME"
nix run /etc/nixos#codex-app
```

The FHS wrapper exposes normal user and temporary paths. Starting it with a
current directory under the host's `/etc` fails because that path is outside
the bubblewrap namespace; launch it from `$HOME`, `/tmp`, or the desktop entry.
The package is deliberately absent from `environment.systemPackages` until
Peter chooses to activate it on a host.

## Update

Read OpenAI's official APT index, select the new `Filename` and `SHA256`, and
update `version`, `url`, and `hash` together:

```text
https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-amd64/Packages
```

Never replace the versioned pool URL with the mutable `/latest/` artifact.
Only `x86_64-linux` is claimed by this derivation; an ARM64 package needs its
own official artifact, hash, build, and launch smoke test.
