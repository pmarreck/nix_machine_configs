# NixOS plan

## Mechatron Prime fleet CI

- [x] Preserve the existing Mechatron Prime module import paths.
- [x] Vendor the receiver, repository policy, worker, and scripts from source commit `b83a195`.
- [x] Add an executable provenance check for the vendored boundary.
- [x] Build source commit `13870e9` from clean committed-tree isolation. Completed 2026-07-10 12:07 EDT.
- [x] Build source commit `097b596` from a new clean committed-tree worktree. Completed 2026-07-10 12:49 EDT.
- [x] Build source commit `b83a195` from a third clean committed-tree worktree. Completed 2026-07-10 13:42 EDT.
- [x] Activate source commit `b83a195` from the clean deployment worktree on the Thelio. Completed 2026-07-10 13:48 EDT.
- [x] Replace the broad Funnel root proxy with explicit `/hooks/github` and `/badges` mounts. Completed 2026-07-10 13:51 EDT.
- [ ] Build and activate source commit `1525b72` so malformed existing badges are repaired without resetting valid live build states. Curiosity poke: parse every served seed with `jq`, not merely inspect its source text.
- [ ] Provision and verify the audited GitHub hooks without exposing their shared secret. Curiosity poke: require whole-set preflight and exact post-mutation counts.
- [ ] Trigger repository builds in controlled waves and verify dynamic badge state transitions. Curiosity poke: verify repaired `capy` advertises package, build, and test targets before its first delivery.
