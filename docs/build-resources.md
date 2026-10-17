# Native job memory containment

`build-budget --project example -- nix develop -c ./test` starts a heavy native
job in a separate user-systemd scope rather than the agent or terminal server's
cgroup. The command keeps its working directory, arguments, terminal and exit
status. It supplies a unique task-owned `TMPDIR` beneath the caller's temporary
directory. Do not replace that directory with shared scratch inside the job.

Two cooperating jobs can run at once. Each has a 12 GiB soft threshold,
16 GiB hard ceiling and no swap. Their aggregate `agentbuilds.slice` has a
24 GiB soft threshold, 32 GiB hard ceiling and 2 GiB swap ceiling. The wrapper
refuses to start unless the expected aggregate hard ceiling is installed.
CPU and I/O weights yield to other work when there is contention; these are
not CPU quotas.

This is containment, not a guarantee against host exhaustion. Existing jobs,
jobs bypassing the wrapper and jobs launched by another service are outside
this slice. Nix daemon builders retain their separate configured envelope.
The slot locks are cooperative, and killing a wrapper while its descendants
survive can release a slot early; the aggregate cgroup still limits those
descendants. A rejected allocation must be investigated, not retried uncapped.

## Receipts and OOM reports

Private completion records are appended to
`${XDG_STATE_HOME:-$HOME/.local/state}/build-budget/runs.ndjson`. A successful
job's scratch is removed only after its scope is inactive; failed or still-live
jobs retain scratch and report its exact path. An exited scope may disappear
before its peak can be read, in which case the receipt records `null` rather
than guessing. The command exit code and systemd's scope result are separate:
a normally exited command can return nonzero while its scope result is success.

Successful scratch cleanup invokes an explicit GNU `rm` executable, never the
caller's guarded `rm` on PATH. Packages pin its Coreutils store path; raw NixOS
source runs default to `/run/current-system/sw/bin/rm`. `BUILD_BUDGET_RM` can
select an absolute executable adapter for direct-source runs. Cleanup retains
the same checks: successful command, inactive scope, existing nonsymlink
directory, and the exact task-owned scratch prefix. Failed cleanup reports a
warning and preserves the command's original status; it does not try another
deletion command.

`build-oom-watch.service` watches new kernel OOM decisions, appends private
`oom.ndjson` records in the same directory and requests critical desktop
notifications. Records identify process name, PID, unit, project when available,
and job-limit versus host exhaustion. The limiting cgroup can be the aggregate
parent rather than the killed process's own cgroup; these paths are kept
separate. A vanished cgroup leaves its peak/limit unknown. Full command lines
are deliberately excluded because they can contain credentials.

The existing hourly temporary-file cleaner now inventories top-level names
without statting user FUSE/AppImage mount roots, which may deny access to root.
Mounts and live process references remain protected, incomplete inspections
abort, and only the existing 24-hour inactive-file policy is applied. This is
conservative inspection, not atomic exclusion against a process opening an old
file after the snapshot.

## Declarative ownership and temporary live bridge

The host module installs the tools for the configured mail-service owner,
defines the aggregate slice and starts the user OOM monitor. Package and unit
outputs can be built without activating the whole system configuration.

An operator may temporarily link those exact immutable outputs into local
user-unit and executable locations, retaining explicit GC roots and rollback
targets. Once the normal full configuration has been activated, verify its
units and package paths, then remove only bridge links whose resolved targets
match the recorded installation. Include the local `default.target.wants`
monitor link. Reload the user manager, restart only the monitor if its executable
changed, and verify the slice limits and terminal-server identity. Do not leave
old home-directory units shadowing future declarative updates. Retire the
bridge's GC roots only after the declarative system owns the same functionality.
