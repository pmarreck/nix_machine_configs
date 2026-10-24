# Mechatron Prime vendored source

The vendored runtime files enumerated by `../test-mechatron-prime-integration`
under `nixos/`, `scripts/`, `ops/`, and `assets/mechatron-prime/`
are copied byte-for-byte from
`pmarreck/mechatron-prime` commit
`76235ec`.

The scheduler, runtime-budget helpers, control/queue CLI, shared package
definitions, operations-page changes and the probe module they depend on are
updated from source commit
`541496e3aa14` (worker startup, coordinator start limit and legacy-migration busy
timeout fixes on top of `ad0f565d5d7f8996bf03c8fd4d5fd0620a904410`). Unrelated receiver, probe and asset
files retain the baseline above. The integration check records each file's
actual digest so this scoped update does not imply a complete source refresh.

Run `../test-mechatron-prime-integration` from this directory (or
`./system76_thelio_nixos/test-mechatron-prime-integration` from the repository
root) before committing an integration update. The check pins every vendored
runtime file's SHA-256 digest and the three stable module-import wrappers.
It does NOT pin file modes: a clobbered executable bit passes every hash.

Update the source repository first, obtain a green source commit, then update
all vendored files and their recorded digests together. Do not patch the vendored
implementation independently; that would split the source of truth.
