# Mechatron Prime host checkup vendored source

`watch/` and `notifications/` are copied byte-for-byte from the `watch/` and
`notifications/` directories of `pmarreck/mechatron-prime` at commit
`dcbd0744af75` (exact-commit CI PASS; the checkup files are unchanged since
`425d0b6766b3`, whose own run stopped on source-fetch: the state lock waits for a coalesced concurrent run;
delivery-only passes return a compact idle result). `ops/probes.lua` and the
Nix wrappers under `nix/` and `nixos/` are host-specific and not pinned to a
source commit.

`watch/queues.lua` and `watch/collect.lua` are then updated from source commit
`64c2cfd`: a direct build scope whose project has a `local/<project>` runtime
approval prompts review only once it outlives that allowance.

`../test-mechatron-prime-integration` pins every vendored Lua file's SHA-256
digest. Update the source repository first, obtain a green exact-commit CI
result, then copy the files and re-record the digests together. Do not patch
the vendored copy independently.
