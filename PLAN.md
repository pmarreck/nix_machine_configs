# NixOS plan

## Mechatron Prime fleet CI

- [x] Preserve the existing Mechatron Prime module import paths.
- [x] Vendor the receiver, repository policy, worker, and scripts from source commit `b83a195`.
- [x] Add an executable provenance check for the vendored boundary.
- [x] Build source commit `13870e9` from clean committed-tree isolation. Completed 2026-07-10 12:07 EDT.
- [x] Build source commit `097b596` from a new clean committed-tree worktree. Completed 2026-07-10 12:49 EDT.
- [x] Build source commit `b83a195` from a third clean committed-tree worktree. Completed 2026-07-10 13:42 EDT.
- [ ] Activate the built NixOS revision on the Thelio. Curiosity poke: activate from the clean deployment worktree so unrelated local indexing and lock-file edits cannot enter the system generation.
- [ ] Replace the broad Funnel root proxy with explicit `/hooks/github` and `/badges` mounts. Curiosity poke: verify `/` and directory listings are not public.
- [ ] Provision and verify the audited GitHub hooks without exposing their shared secret. Curiosity poke: require whole-set preflight and exact post-mutation counts.
- [ ] Trigger repository builds in controlled waves and verify dynamic badge state transitions. Curiosity poke: verify repaired `capy` advertises package, build, and test targets before its first delivery.
