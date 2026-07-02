# Kickoff: NixOS channels → flake migration (from orchestrator / thelio-pm)

**Date:** 2026-07-05 · **From:** orchestrator session · **Type:** LLMsend kickoff

## Purpose & intent
Migrate this host (`system76_thelio_nixos/`) from imperative `nix-channel`/`NIX_PATH`
sources to a git-tracked **flake** (`flake.nix` + `flake.lock`). Peter wants off
channels (they silently rotted — `nixos-unstable` was stuck 500k commits back,
`nixos-master` never updated) and onto pinned, reproducible, in-repo inputs.

## READ FIRST
- **`/etc/nixos/FLAKE_MIGRATION_PLAN.md`** — the full, file-by-file plan (pre-flight
  file-tracking audit, two impure-fetch BLOCKERS, flake.nix skeleton, build-before-boot
  gate, rollback rail, ixnay wrapper changes, risks). Follow it. It was written this
  session against the real files.

## Decisions — use these defaults (the plan's recommendations); don't stall on them
1. Base `nixpkgs` input: **follow `github:NixOS/nixpkgs/nixos-unstable`** (rolling, matches current base).
2. `unstable` scope: **reuse the base input** (`import inputs.nixpkgs { … allowUnfree }`) — one input, no dup eval.
3. `master` scope: **drop it** — repoint its ~9 packages (`master.gum`, `master.protontricks`, `master.signal-desktop`, `master.visidata`, `master.whatsapp-for-linux`, `master.winetricks`, `master.youtube-dl`, …) to `unstable.*`. (On an unstable base, master buys nothing and risks eval breakage.)
4. `stable` scope: **follow the `release-26.05` branch** (so `nix flake update` rolls it). The config currently pins rev `721be2608f425037939026ef94839680fe67b9a4`; a branch-follow input supersedes the inline pin.
5. `nixos-hardware`: **omit** (current config doesn't use it).
6. The two impure fetches: **fix properly** (don't ship `--impure`): vendor the clocksound gist as a tracked `clocksound.bash` + `readFile`; pin the adi1090x-plymouth `fetchGit` to a rev (or `fetchFromGitHub` w/ sha256).

## Hard guardrails (this is a daily-driver boot config on ZFS root)
- **jj ONLY, never raw git** (a hook blocks it). Main bookmark `yolo`.
- **jj-track every referenced file BEFORE building** — flakes see only git-tracked files; an untracked one aborts eval with a confusing "No such file or directory". The plan's §0 lists them.
- **Build, do NOT boot.** Gate: `nixos-rebuild build --flake /etc/nixos#nixos` → `nvd diff /run/current-system ./result` → STOP. **Do not `switch`/`boot`/activate.** Leave the actual cutover for Peter to run (`ixnay reify`) after he reviews the diff.
- **Keep the channels subscribed** as the rollback rail; don't `nix-channel --remove` anything.
- The config already builds green on channels today (verified this session) — so a clean `build --flake` + a sane closure diff is your success criterion.

## Deliverable & reporting
- A working `flake.nix` + `flake.lock`, `configuration.nix` converted to receive `unstable`/`stable`/`inputs` via `specialArgs`, both blockers fixed, **verified only via `build --flake` (not activated)**.
- Update the `ixnay` reify command per plan §5 (its own repo `~/Code/ixnay`, TDD there) — OPTIONAL, flag if out of scope.
- Report back to `~/inbox/` on the thelio-pm host (orchestrator runs in `$HOME`) with: the diff summary, anything that needed a real decision, and the exact command Peter should run to cut over. Do NOT merge to `yolo` or activate.
