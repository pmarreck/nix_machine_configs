---
purpose: Step-by-step plan to migrate the thelio NixOS host from nix-channels to a git-tracked flake
audience: both
maintained_by: agent
generated_from: Plan-agent read-only analysis of the live config, 2026-07-02
---

# FLAKE_MIGRATION_PLAN.md

Migrate the **thelio** NixOS host (`system76_thelio_nixos/`) from imperative `nix-channel` / `NIX_PATH` sources to a git-tracked **flake** (`flake.nix` + `flake.lock`). TDD-style: build-before-boot gate at every step, prior GRUB generations as the rollback rail. Every claim below was verified against the real files (config = `system76_thelio_nixos/configuration.nix`, 1713 lines, symlinked as `/etc/nixos/configuration.nix`).

---

## Open decisions for Peter (need your call before step 2)

1. **Base `nixpkgs` input pin.** Current base is `nixos-unstable` (26.11pre, rolling). Recommend `inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"`. Alternative: pin an exact rev for full determinism, move only via `nix flake update`. **Rolling vs. reproducible?**
2. **Reuse base for the `unstable` scope, or a separate input?** In your old attempt, `nixpkgs` and `unstable` locked to the *identical* rev. Recommend `unstable = import inputs.nixpkgs { … allowUnfree }` (one input, no duplicate eval).
3. **Keep the `master` scope?** Genuinely used (9 refs: `master.gum`, `master.protontricks`, `master.signal-desktop`, `master.visidata`, `master.whatsapp-for-linux`, `master.winetricks`, `master.youtube-dl`, …). Options: (a) add `nixpkgs-master.url = "github:NixOS/nixpkgs"`; (b) drop `master`, repoint those at `unstable.*`. **Recommend (b)** — on an unstable base, `master` buys little and risks eval breakage.
4. **`stable` input: exact rev vs. follow-branch.** Currently pinned in-config to rev `721be2608f425037939026ef94839680fe67b9a4` (release-26.05). As a flake input: pin that rev, or follow a `nixos-25.05`/`release-26.05` branch that `nix flake update` bumps. Recommend **branch-follow** so `ixnay reify --upgrade` rolls it too.
5. **`nixos-hardware`?** Old attempt imported `nixos-hardware.nixosModules.system76`; current config does **not**. Recommend **omit** for parity; add later deliberately.
6. **`--impure` escape hatch?** Two eval-time impure fetches must be fixed for pure eval (see Blockers). Recommend fixing properly rather than shipping with `--impure`.

---

## 0. Pre-flight — file tracking & impurity audit (do FIRST)

Flakes evaluate **only git-tracked files**. jj colocated repos: any `jj` command snapshots the working copy into a git commit, so a newly created `flake.nix` becomes visible after the next `jj` invocation.

- [ ] **Every imported/read path is git-tracked** — verified all present & tracked: `hardware-configuration.nix` (imported), `zfs.nix` (imported), `firefox-overlay.nix` (overlay), `packages/default.nix` + `packages/adi1090x-plymouth` (overlay), `key-rebel-moon.nix` + `tech-alive.nix` (callPackage), the three root symlinks. Re-verify after any `mv`/rename — one untracked file aborts the whole eval.
- [ ] **Current dirty working copy is fine.** `jj status` shows `M …/configuration.nix` (this session's stable-pin edit). Flakes see *modifications to tracked files*; they only miss *untracked new files*. `nix.settings.warn-dirty = false` (line 1701) already suppresses the warning.
- [ ] **Bookmark:** main is `yolo`. Do flake work there.
- [ ] **All angle-bracket `<…>` NIX_PATH lookups** (break under pure eval): line **29** `import <nixos-unstable>` → `inputs.nixpkgs`; line **50** `import <nixos-master>` → `inputs.nixpkgs-master` (or dropped). `packages/adi1090x-plymouth` line 2 `pkgs ? import <nixpkgs> {}` is an inert default arg (callPackage passes `pkgs`) — tidy but harmless. No `<nixpkgs>`/`<nixos-stable>`/`<nixos-hardware>` remain in main config.
- [ ] **Experimental features already live** — `nix.settings.experimental-features = [ "nix-command" "flakes" ]` (line 1700). Fallback: `--extra-experimental-features 'nix-command flakes'` on the first build.

### BLOCKERS — two eval-time impure fetches that fail pure eval

- [ ] **`builtins.fetchurl` without a hash — clocksound.** Line **340**: `scriptContent = builtins.readFile (builtins.fetchurl scriptUrl);` (live hourly systemd user service). **Fix (recommended):** vendor the gist as tracked `system76_thelio_nixos/clocksound.bash` and `builtins.readFile ./clocksound.bash` — pure, and drops a network dependency from your boot config. Alt: pin `fetchurl { url; sha256; }`.
- [ ] **`builtins.fetchGit` without a rev — adi1090x-plymouth.** `packages/adi1090x-plymouth` lines 8–10: `src = builtins.fetchGit { url = "https://github.com/adi1090x/plymouth-themes"; };` — reached via Plymouth `theme = "metal_ball"` (line 262). **Fix:** pin `rev`+`ref`, or convert to `pkgs.fetchFromGitHub { … sha256 = …; }` for parity with your other pins.

### Already pure — do NOT touch
`stable` pinned tarball (has sha256), `comma` fetchFromGitHub, GRUB theme fetchFromGitHub, `builtins.getFlake "github:modem-dev/hunk/0a3cc064…"` (fully locked rev; harmless x86_64-darwin warning already documented).

---

## 1. `flake.nix` design (git-track it, then build — never boot first)

Create `/etc/nixos/flake.nix` at the repo root (so `--flake /etc/nixos#thelio-nixos` resolves and the symlinks keep working):

```nix
{
  description = "Peter's thelio NixOS system";

  inputs = {
    nixpkgs.url        = "github:NixOS/nixpkgs/nixos-unstable";   # base + `unstable` (dec 1/2)
    nixpkgs-master.url = "github:NixOS/nixpkgs";                   # `master` (dec 3 — optional)
    nixpkgs-2605.url   = "github:NixOS/nixpkgs/nixos-25.05";       # `stable` (dec 4 — or pin rev 721be26…)
  };

  outputs = { self, nixpkgs, nixpkgs-master, nixpkgs-2605, ... }@inputs:
    let
      system = "x86_64-linux";
      mkUnfree = src: import src { inherit system; config.allowUnfree = true; };
    in {
      nixosConfigurations.thelio-nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          unstable = mkUnfree nixpkgs;         # reuse base input (dec 2)
          master   = mkUnfree nixpkgs-master;  # omit if dropping master
          stable   = mkUnfree nixpkgs-2605;
        };
        modules = [ ./system76_thelio_nixos/configuration.nix ];
      };
    };
}
```

- **Why per-scope `import … { config.allowUnfree = true; }`:** independent nixpkgs instantiations, each needs its own `allowUnfree`, mirroring lines 30/49/51.
- **Why NOT pass `pkgs` in specialArgs:** let the module system build base `pkgs` from `nixpkgs.config`/`nixpkgs.overlays` so `allowUnfree` (419), `permittedInsecurePackages` (121–124), and both overlays (116–117) keep working.
- **Exact-rev `stable` alt:** `nixpkgs-2605.url = "github:NixOS/nixpkgs/721be2608f425037939026ef94839680fe67b9a4";`

Steps: create `flake.nix` → `jj status` (snapshot so the flake sees itself; confirm `git ls-files | rg flake.nix`) → `nix flake lock /etc/nixos` → `jj status` again (track `flake.lock`) → `mv ~/.Trash/` the tracked `flake.nix.old_attempt` + `flake.lock.old_attempt` (nixos-22.05/home-manager cruft) → `jj status`.

---

## 2. `configuration.nix` edits

- [ ] **Module signature** (line 6): `{ options, config, pkgs, lib, ... }:` → `{ options, config, pkgs, lib, unstable, master, stable, inputs, ... }:` (drop `master` if dec 3=b).
- [ ] **Delete the three `let` bindings** now injected: `unstable` (29–38), `stable` (46–49), `master` (50–52). Keep `key-rebel-moon`, `tech-alive`, `erlang = unstable.erlang`, `elixir`, `comma`.
- [ ] **Re-grep for residual `<…>`** after editing.
- [ ] **Apply the two blocker fixes** (clocksound 340; plymouth fetchGit).
- [ ] **`system.autoUpgrade`** (1680–1681): `autoUpgrade.channel = …nixos-26.05;` is meaningless under flakes → `autoUpgrade.flake = "/etc/nixos#thelio-nixos";` (+ optional `flags = [ "--update-input" "nixpkgs" ]`), or disable and let `ixnay reify` be the sole path.
- [ ] **Leave `nix.settings` as-is** (1685–1704). Optionally add `nix.registry.nixpkgs.flake = inputs.nixpkgs;` so ad-hoc `nix run nixpkgs#…` matches the system.

---

## 3. Build-before-boot gate (the "test")

- [ ] **Realize without activating:** `nixos-rebuild build --flake /etc/nixos#thelio-nixos` (or `nix build /etc/nixos#nixosConfigurations.thelio-nixos.config.system.build.toplevel`). Produces `./result`; touches nothing live. This is the failing-test-first gate.
- [ ] **Diff candidate vs. live BEFORE boot:** `nvd diff /run/current-system ./result` (or `nix store diff-closures …`). Independent check that the flake reproduces today's closure — unexpected package moves surface here.
- [ ] **Only after clean build + sane diff:** `sudo nixos-rebuild boot --flake /etc/nixos#thelio-nixos`, then reboot. Prefer `boot` over `switch` for the first cutover (ZFS-root safe; matches ixnay's default).

---

## 4. Rollback rail

- [ ] Prior channel-based generation stays in GRUB (`configurationLimit = 10`, line 171) — pick it at the menu, instant.
- [ ] Keep channels subscribed until N≈3 successful flake boots (a channel-based `sudo nixos-rebuild boot` stays a working escape hatch).
- [ ] Config revert: `jj` the flake edits away, `sudo nixos-rebuild boot` old-style.
- [ ] After N good boots: optionally `sudo nix-channel --remove nixos-unstable nixos-master nixos-stable nixos-hardware` and prune comments — the deliberate point of no easy return.

---

## 5. `ixnay` wrapper changes (`~/Code/ixnay/bin/ixnay`, its own repo — TDD there)

`reify` command lines 443–496; rebuild invocations 472–480; `SWITCH_OR_BOOT` default line 261.

- [ ] **Reify no-upgrade (474):** `sudo nixos-rebuild $SWITCH_OR_BOOT` → `… --flake /etc/nixos#thelio-nixos`.
- [ ] **Reify upgrade (478–480):** `--upgrade` is a channel concept → replace with `sudo nix flake update --flake /etc/nixos && sudo nixos-rebuild $SWITCH_OR_BOOT --flake /etc/nixos#thelio-nixos`. This IS "roll" for a flake.
- [ ] **Optional targeted roll:** `--update-input nixpkgs` (base only) vs full `nix flake update` (all scopes) — matches the "simulate rolling release" intent.
- [ ] Leave the macOS/nix-darwin branch (497–517) — already flake-based.
- [ ] `rollback|rb` (783–790) is user-profile; document that *system* rollback is the GRUB previous-generation menu; optionally add `nixos-rebuild --rollback`/`list-generations`.
- [ ] Update `#help` + add a CLI test asserting the emitted command contains `--flake /etc/nixos#thelio-nixos` and no `--upgrade` on NixOS (ixnay renders the command before running — cheaply DRY_RUN-testable).

---

## 6. Risks & footguns

- **Untracked-file eval death** (#1 gotcha): new files invisible until a `jj` snapshot. Always `jj status` + `git ls-files | rg <name>` before building. Symptom: `error: … No such file or directory` for a file that plainly exists.
- **The two impure fetches (§0):** most likely first-build failures. Fix, or `--impure` stopgap.
- **NIX_PATH removal:** `<nixpkgs>` gone under `--flake`; interactive `nix-shell -p`/scripts change — use `nix run nixpkgs#…` / a registry entry.
- **`master` drift:** on an unstable base, `nixpkgs/master` can eval-break — folding into `unstable` (dec 3b) shrinks the surface.
- **Dirty-tree eval:** fine here; but uncommitted renames/new files still need a snapshot.
- **`hunk` getFlake warning:** expected, already litigated in comments — don't chase.
- **ZFS-root boot:** prefer `boot` not `switch` for cutover; `DefaultTimeoutStopSec = "30s"` (line 334) reduces wedged-shutdown risk; keep 10 generations.

---

### Critical files
- `/etc/nixos/flake.nix` (create — core)
- `/etc/nixos/system76_thelio_nixos/configuration.nix` (sig line 6; delete `let` 29–52; blocker 340; autoUpgrade 1680–1681)
- `/etc/nixos/system76_thelio_nixos/packages/adi1090x-plymouth` (hashless fetchGit, 8–10)
- `/home/pmarreck/Code/ixnay/bin/ixnay` (reify rebuild cmds 472–480)
- `flake.lock.old_attempt` (reference; to be untracked)
