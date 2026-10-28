# Mechatron Prime vendored source

The vendored runtime files enumerated by `../test-mechatron-prime-integration`
under `nixos/`, `scripts/`, `ops/`, and `assets/mechatron-prime/`
are copied byte-for-byte from
`pmarreck/mechatron-prime` commit
`76235ec`.

The scheduler, runtime-budget helpers, control/queue CLI, shared package
definitions, operations-page changes and the probe module they depend on are
updated from source commit
`541496e3aa14` (worker startup, coordinator start limit and legacy-migration busy
timeout fixes on top of `ad0f565d5d7f8996bf03c8fd4d5fd0620a904410`). Unrelated receiver, probe and asset
files retain the baseline above. The integration check records each file's
actual digest so this scoped update does not imply a complete source refresh.

The activation change policy (`stopIfChanged = false` on the webhook receiver,
badge server, ops console, operator route and provisioner) is updated from
source commit `44eb1c1` so an interrupted switch cannot leave those services
stopped; the receiver file keeps its baseline badge MIME-type divergence and
the provisioner copy under `../mechatron-prime-provision/` carries the same hunk.

The operator control script (`scripts/mechatron-prime-control`) is updated from
source commit `a2201be8b2a9`, which adds `retry --project P --commit SHA` for
commits whose run stopped before the source was fetched; the pinned digest
follows that commit.

The worker and its policy library (`scripts/worker.bash`, `scripts/policy.bash`)
are updated from source commit `c3877d05f3d1`, which retries a source fetch
once after its own hang bound fires and logs lane stall snapshots for each
failed attempt; both pinned digests follow that commit.
The worker is then updated from source commit `af9784a`, which keeps a garbage-
collection root on the newest green output of each repository, branch and
target; its pinned digest follows that commit.

The worker, policy library and worker module are then updated from source
commit `e2cbfe4`, which repacks the worker's ref-less Nix fetcher cache with
`git repack --geometric=2 -d` between jobs once it holds 50 packs, under a
lease that keeps a repack from running under another lane's fetch. The
module names the cache directory, which enables the maintenance.

The worker, ledger library, history CLI and ops ledger projection and renderer
are then updated from source commit `7a26eb4`. Each CI run reports its targets
with their own outcomes in `/ops/ci-log.json`, the CI projection's recent runs
and `mechatron-ci log`; targets after a failed or stopped one are recorded as
`skipped` (ledger schema version 3, a table rebuild on the worker's first
start); and each run log ends with a result block.

The ops process adapter, policy library and worker are then updated from
source commit `378eeb7`. The adapter reports a command's real exit status
(LuaJIT's default mode returned success from every popen close, so failed ops
actions showed as done), and a commit with no target manifest, or one listing
no targets, publishes a grey `UNCONFIGURED` badge instead of `FAILING`.

The queue claim library is then updated from source commit `abaa153`: a lane's
claim takes the superseded commits of the build it selects (same repository
and branch) into the same batch, ahead of the build, so their verdicts no
longer wait behind every later build of a frequently pushed branch.

The queue claim library and policy library are then updated from source commit
`64c2cfd`: the queue keeps arrival order and stores no superseded marks, so a
claim can no longer read a branch's moved-up newest commit as its oldest and
supersede it, which had left a branch's newest commit unbuilt.

Run `../test-mechatron-prime-integration` from this directory (or
`./system76_thelio_nixos/test-mechatron-prime-integration` from the repository
root) before committing an integration update. The check pins every vendored
runtime file's SHA-256 digest and the three stable module-import wrappers.
It does NOT pin file modes: a clobbered executable bit passes every hash.

Update the source repository first, obtain a green source commit, then update
all vendored files and their recorded digests together. Do not patch the vendored
implementation independently; that would split the source of truth.
