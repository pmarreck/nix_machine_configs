# NixOS plan

## Flake portability gate (2026-07-26)

- [x] Gate machine-local flake inputs. The `ollama` input was added as
  `path:/home/pmarreck/Code/ollama` — "intentionally local until its upstream
  push", per its own comment — which made `nix flake update` fail on the
  framework laptop days later, and made the flake unevaluable by any CI.
  Three layers, strongest last: `.githooks/pre-commit` warns, `.githooks/pre-push`
  blocks (shipped via tracked `.githooks` + `core.hooksPath`, so it travels with
  the clone; `bin/install-git-hooks` is the one-time per-clone bootstrap), and
  `.github/workflows/flake-portability.yml` enforces it where `--no-verify`
  cannot reach. Checker: `bin/check-flake-portability`; suite: `./test`.
  - Curiosity poke answered: NOT every `path:` input is bad — a relative in-repo
    one (`path:./modules/foo`) is perfectly portable, so the rule is "absolute
    path or `file://` URL", and the test suite partitions a mixed SET of five
    inputs rather than checking one example. Mutation-tested both ways: disabling
    detection fires 5 assertions, an over-broad rule fires exactly the 2
    anti-overreach assertions.
  - CI is the only non-bypassable layer; a runner has no `/home/pmarreck`, so it
    fails on a machine-local input by construction.

- [ ] Fix the `ollama` input itself — the gate currently (correctly) refuses this
  repo. The fork's `flake.nix` was never committed to `github.com/pmarreck/ollama`
  (search shows zero commits touching it), so that work exists only in the
  Thelio's `~/Code/ollama` working tree, on a machine with a suspect disk.
  Recover it, push a branch, then switch the input to
  `url = "github:pmarreck/ollama/<branch>"`.
  - `flake.lock` recorded the snapshot as
    `narHash = "sha256-bVfK3wfGegz5cCH+D/pgCI8qobSZcEd5cuSV7/zJr0M="`
    (taken 2026-07-23 10:05 EDT), so the exact content should still be in the
    Thelio's nix store even if the working tree is damaged.

## System packages

- [x] Add `libarchive` to the Thelio's declarative global package set and
  validate the locked flake without activating it.
  (2026-07-17 12:59 EDT)
  - Curiosity poke: confirm both the package derivation and its expected
    `bsdtar` executable are present in the candidate system closure.

## Mechatron Prime fleet CI

- [x] Persist the already-running NVMe Nix/Steam/dev-cache mount configuration in a reviewed green commit. Completed 2026-07-22 12:33 EDT.
  - Curiosity poke answered: the combined candidate differed from the running closure only by Mechatron Prime, proving the committed storage configuration retains all three imported ZFS pools and `/nix` build-dir placement.
- [x] Vendor, build, and activate Mechatron Prime source commit `f74aec6`, including resilient worker exit semantics and the transactional SQLite result ledger. Completed 2026-07-22 12:35 EDT.
  - Curiosity poke answered: the deployed empty drain is inactive/successful, source tests retain a failing broken-database prerequisite, and public latest plus commit-specific projections passed live checks.

- [x] Preserve the existing Mechatron Prime module import paths.
- [x] Vendor the receiver, repository policy, worker, and scripts from source commit `b83a195`.
- [x] Add an executable provenance check for the vendored boundary.
- [x] Build source commit `13870e9` from clean committed-tree isolation. Completed 2026-07-10 12:07 EDT.
- [x] Build source commit `097b596` from a new clean committed-tree worktree. Completed 2026-07-10 12:49 EDT.
- [x] Build source commit `b83a195` from a third clean committed-tree worktree. Completed 2026-07-10 13:42 EDT.
- [x] Activate source commit `b83a195` from the clean deployment worktree on the Thelio. Completed 2026-07-10 13:48 EDT.
- [x] Replace the broad Funnel root proxy with explicit `/hooks/github` and `/badges` mounts. Completed 2026-07-10 13:51 EDT.
- [x] Build and activate source commit `af3440b` so canonical allowlist and target policy replace stale pilot files. Completed 2026-07-10 16:20 EDT.
  - Curiosity poke: parse every served seed with `jq`, not merely inspect its source text.
- [x] Vendor Mechatron Prime source commit `fac63a6`, including operations-console refinements and randomized JPEG XL explainer assets. Completed 2026-07-11 13:42 EDT.
  - Curiosity poke: every vendored runtime file must remain byte-for-byte tied to the declared source commit.
- [x] Vendor Mechatron Prime source commit `5b3c4fb`, adding `validate_gui`'s Linux GUI build gate plus verified Codex, ZFS, and NetHogs operations refinements. Completed 2026-07-11 23:06 EDT.
  - Curiosity poke answered: the candidate closure contains the exact audited GUI target, `UNKNOWN` badge seed, and only `/home/pmarreck/.codex` as the ops service's writable home path.
- [x] Vendor and build Mechatron Prime source commit `46db1db`, registering FSearch's package, build check, and test check. Completed 2026-07-14 16:22 EDT.
  - Curiosity poke answered: the candidate and running system share exact Nixpkgs revision `0bb7ec54`; the closure adds only FSearch and the previously pending `validate_gui` policy seeds.
- [x] Vendor and build Mechatron Prime source commit `34851fa`, making the worker and webhook honor each repository's declared default branch (FSearch: `master`). Completed 2026-07-14 17:18 EDT.
  - Curiosity poke answered: the unactivated closure contains FSearch's `master` policy plus package, build, and test targets; Peter must still inspect the activation diff before a live switch.
- [ ] Activate the reviewed closure, provision FSearch's exact GitHub webhook, and verify `UNKNOWN` then `PASSING` through the public badge route.
  - Curiosity poke: activation also applies the already-committed operations-console executable and restart-policy updates, so it requires explicit approval despite no GUI/audio/kernel/package drift.
- [ ] Review `ixnay reify --no-update` dry activation before making the new `thelio-nixos` generation the next boot target.
- [ ] Provision and verify the audited GitHub hooks without exposing their shared secret. Curiosity poke: require whole-set preflight and exact post-mutation counts.
- [ ] Trigger repository builds in controlled waves and verify dynamic badge state transitions. Curiosity poke: verify repaired `capy` advertises package, build, and test targets before its first delivery.
