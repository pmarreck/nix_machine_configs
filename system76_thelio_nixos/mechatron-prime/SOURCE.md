# Mechatron Prime vendored source

The vendored runtime files enumerated by `../test-mechatron-prime-integration`
under `nixos/`, `scripts/`, `ops/`, and `assets/mechatron-prime/`
are copied byte-for-byte from
`pmarreck/mechatron-prime` commit
`26bbe00`.

Run `../test-mechatron-prime-integration` from this directory (or
`./system76_thelio_nixos/test-mechatron-prime-integration` from the repository
root) before committing an integration update. The check pins every vendored
runtime file's SHA-256 digest and the three stable module-import wrappers.

Update the source repository first, obtain a green source commit, then update
all vendored files and their recorded digests together. Do not patch the vendored
implementation independently; that would split the source of truth.
