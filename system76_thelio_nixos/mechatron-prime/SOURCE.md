# Mechatron Prime vendored source

The files under `nixos/` and `scripts/` are copied byte-for-byte from
`pmarreck/mechatron-prime` commit
`b83a1953266cfa13dbf35f127dfa3477c3148938`.

Run `../test-mechatron-prime-integration` from this directory (or
`./system76_thelio_nixos/test-mechatron-prime-integration` from the repository
root) before committing an integration update. The check pins every vendored
file's SHA-256 digest and the two stable module-import wrappers.

Update the source repository first, obtain a green source commit, then update
the six files and their recorded digests together. Do not patch the vendored
implementation independently; that would split the source of truth.
