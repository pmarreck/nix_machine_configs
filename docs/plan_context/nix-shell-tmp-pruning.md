# Stale `nix develop` temporary directories

## Report

On 2026-11-19, the `mecha_beamflix` agent reported that runtime-limited
`build-budget` jobs can leave `/tmp/nix-shell.*` directories behind. It reported
568 directories totaling about 11 GB, aged roughly 7–11 hours, and said no
running process environment referenced them. These counts and reference checks
have not been independently verified. The note also reports owner approval for
irrecoverable deletion of genuinely stale directories.

The scheduled hourly `/tmp` cleaner currently deletes old unreferenced entries
only after 24 hours and fails closed if process-reference inspection is
ambiguous. At the noon 2026-11-19 check, `/tmp` was 55% used with about 11 GB
available; the latest cleaner pass removed nine entries with no errors. There
were 58 `/tmp/nix-shell.*` directories at that observation. No extra deletion
was done.

## Before implementation

- Confirm the minimum age threshold. The request says “a few hours” but does not
  define an exact cutoff.
- Restrict candidates to real, non-symlink `/tmp/nix-shell.*` directories
  owned by the intended user; never recurse across mounts or accept escaped
  paths.
- Protect any directory referenced by a live process through its environment
  (`TMPDIR`), working directory, open descriptors, executable or mappings.
  Incomplete `/proc` visibility, permission failures, ambiguous paths or a scan
  race must skip deletion and report the reason.
- Prefer an exact per-job cleanup association on timeout if `nix develop`
  exposes a dependable shell directory; otherwise extend the guarded hourly
  cleaner with isolated tests for age, ownership, references, races and failure
  behavior.
- Keep the change source-first: fix and test the canonical Mechatron source,
  then sync the NixOS vendor copy and run its required test/build gates before
  activation.
