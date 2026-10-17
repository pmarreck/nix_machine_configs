# Herdr hooks and Collie: scoped Python runtime

## Why this exists

Herdr 0.8.2 installs shell hooks for Claude, Codex and Grok which silently exit
when `python3` is absent. Agents still work, but their conversation identities
never reach Herdr. Collie 1.5.1 then hides their history links and its update
preflight fails `hook-python3` and `agent-sessions`.

Peter explicitly does not want Python on the global/user PATH. The package
`herdr-hook-runtime` supplies it only inside the hooks and the `collie-runtime`
command. It exports no `python` or `python3` executable. No Python was added to
systemPackages, user packages, shell startup, or the Herdr service environment.
This is dependency scoping, not a security sandbox denying access to the store.

## Definitions and tests

- `packages/herdr-hook-runtime.nix` uses the flake-pinned Herdr hook sources.
  The sole hook change adds a Nix-pinned PATH inside the hook process. Upstream
  protocol handling and version markers are retained.
- The CLI wrapper executes the vendor's mutable Collie `current/bin/collie`;
  Collie's existing self-update and rollback mechanism remains available.
- `tests/herdr_hook_runtime_check.py` exercises each upstream and packaged hook
  against a temporary Unix socket with a child PATH that lacks Python. It checks
  the original silent failure, real identity reporting, irrelevant events,
  missing IDs, and the absence of public Python executables. Python is used here
  as the dependency's test driver and stdlib Unix-socket receiver.
- `tests/herdr_hook_runtime_test.sh` builds that check through the ordinary
  `./test` suite. No live agent or socket participates in automated tests.

The scoped check passed. The full 2026-09-08 host suite ran 21 test files with
three failed assertions caused by the separate locked `tmog.org/version.txt`
narHash mismatch (TMOG's two checks and aggregate target resolution). No host
activation or unrelated input update was attempted; changes are uncommitted
pending a fully green suite.

## Live installation on Thelio (2026-09-08)

The package is GC-rooted through `$HOME/.local/state/herdr/hook-runtime`:

```bash
nix build /etc/nixos#herdr-hook-runtime \
  --out-link "$HOME/.local/state/herdr/hook-runtime"
```

The three existing managed hook paths contain byte-identical copies of the
package's `share/herdr-hooks/{claude,codex,grok}.sh`. Hook registrations remain
unchanged, including Grok's required `$HOME/.grok/hooks/herdr.json`. Grok needs
no additional plugin for this integration.

Original hooks are backed up at
`$HOME/.local/state/herdr/backups/20260908-scoped-hooks/`.

`$HOME/.local/bin/collie-runtime` forwards to the GC-rooted wrapper. The user
service drop-in `$HOME/.config/systemd/user/collie.service.d/20-scoped-runtime.conf`
clears `ExecStart` and uses that same wrapper with `_exec-bridge`. It does not
change ports, ingress, credentials, the vendor unit, or the Herdr service.
Only Collie was restarted. All 21 supported live panes subsequently reported
session IDs; all three integrations were current; private HTTPS returned 200.

Use:

```bash
collie-runtime doctor --plain
collie-runtime update --check --local --plain
collie-runtime update
```

Alternatively: `nix run /etc/nixos#herdr-hook-runtime -- doctor --plain`.
The ordinary `collie` symlink remains vendor-owned. Running it directly from a
Python-free shell still trips 1.5.1's *caller-PATH* check, even though the hooks
now work. Use `collie-runtime`; do not install global Python to placate that check.
The bridge's own update commands inherit the scoped runtime from its service.
The repair left Collie at 1.5.1; preflight verified that 1.6.0 is available.

## Reinstalling or updating Herdr integrations

Upstream integration installation overwrites these managed hook files. After
updating the Herdr input or reinstalling its integrations, rebuild this package
from the matching pin, back up the current hooks, and deploy its three hook files
to the existing installed paths. Preserve executable modes and compare bytes.
Do not keep an older packaged script merely to suppress a version warning.
This reapplication is manual for now, not an unimplemented automatic guarantee.

Current sessions need no restart just to associate their identities. The repair
replayed each actual installed SessionStart hook against its own Herdr pane,
using verified process arguments/open rollout files and native conversation IDs.
Never guess IDs or start another writer to obtain one. Hook events in future
sessions use the same fixed paths automatically.

## Rollback

Restore the backed-up hook scripts and remove the Collie drop-in recoverably.
Reload the user manager and restart **only** `collie.service`. The original
Collie binary/symlink, configuration, and all agent histories remain intact.
Do not restart Herdr: that would terminate its live agent processes.

Keep private ingress on port 8446. Collie's earlier default-port collision with
Mechatron's public 443 handlers is a separate known incident; do not recreate it.
