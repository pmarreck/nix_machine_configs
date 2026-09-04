# NixOS plan

## Install Hunk on Tiki-WSL (2026-09-04)

- [ ] Add a failing package/placement contract for the exact Hunk derivation
      already running on Thelio, then replace Thelio's embedded flake lookup
      with one locked top-level input shared with Tiki.
  - Curiosity poke: identify the package by upstream, revision, `pname`, and
    reported version so an unrelated project named Hunk cannot satisfy it.
- [ ] Expose and build an executable smoke check, build the exact Tiki host
      closure, inspect activation effects, push, and verify exact-commit CI.
  - Curiosity poke: install the CLI in Tiki's active `nixos` user profile and
    avoid changing unrelated host packages or the host Nixpkgs revisions.

## Herdr on Thelio (2026-09-04)

- [x] Reproduce why the live user service discovers Codex but not Peter's
      Claude or Grok launchers, then add a failing effective-environment test
      and give Herdr the smallest declarative executable path that matches the
      relevant entries produced by `~/dotfiles/.pathconfig`.
  - Curiosity poke: do not source an interactive shell configuration inside a
    systemd daemon; wrappers may depend on shell functions or mutable state,
    and an unrestricted inherited PATH could change behavior after activation.
  - Completed 2026-09-04 09:04 EDT. Mechatron Prime `76235ec` adds only the
    stable `~/.local/bin` and `~/.grok/bin` launcher directories and explicitly
    resolves NixOS's default user-service PATH precedence. The effective Nix
    regression, complete 14-file host suite, exact Thelio build, dry activation,
    live switch, and Mechatron CI pass at host commit `9daa738`. The service was
    restarted and its live process environment contains both directories.
- [x] Change Herdr's command-prefix binding from `Ctrl-B` to `Ctrl-Space`
      declaratively and verify that Herdr accepts the resulting configuration.
  - Curiosity poke: preserve literal space handling through Nix, TOML, and
    Herdr's key parser rather than guessing at the binding spelling.
  - Completed 2026-09-04 09:04 EDT. Dotconfig commit `97b0714` tracks the
    accepted `ctrl+space` spelling and ignores runtime sockets/state. Herdr
    live-reloaded the config. Its official installers now report Claude v9,
    Codex v8, and Grok v1 current; a second install was byte-identical. The
    prior Claude settings are recoverable from
    `~/.Trash/herdr-integrations-before-20260904-0905`.

- [x] Pin upstream Herdr 0.8.2 through its first-party flake without changing
      the host's own Nixpkgs revision. Completed 2026-09-04 08:18 EDT.
- [x] Vendor green Mechatron Prime commit `a61097e`, which declares Peter's
      lingering `herdr.service` and exact status/start/stop/restart operations
      controls. Completed 2026-09-04 08:18 EDT.
- [x] Evaluate and build the exact Thelio closure; verify Herdr's package,
      foreground server command, and `default.target` wiring. Completed
      2026-09-04 08:19 EDT.
- [x] Activate the candidate, then prove the user daemon, Unix-socket CLI,
      tailnet ops status, and all three mutation controls without touching the
      existing tmux fleet.
  - Curiosity poke: Herdr's user service must remain in `user.slice` with
    read-write access to Peter's home, even when controlled by the hardened
    root-owned operations service.
  - Completed 2026-09-04 08:24 EDT. The live generation is
    `/nix/store/fxzg3jlmslj0j6cs76cymj5cplkbqph9-nixos-system-thelio-nixos-26.11.20260807.f13ff45`;
    Herdr runs in `user.slice`, its server/socket protocol check passes, and
    all three tailnet operations-page mutations were proven against systemd.

## Roll back failed detached Codex mail wake (2026-09-03)

- [x] Disable Thelio's detached Codex PTY wake after the live proof reproduced
      a client disconnect without delivering the mail notification. Preserve
      active terminal wake for Claude/Grok and passive Codex notices, then test,
      dry-activate, switch, and verify the service environment.
      - Curiosity poke: Peter accepted the previously measured interruption
        risk, but the experiment delivered no compensating wake benefit. The
        terminal path therefore fails its own usefulness criterion.
      Completed 2026-09-03 21:25 EDT. The RED host contract failed on the live
      true value, then passed after the rollback. All 11 configuration test
      files and the privileged dry activation passed; the live generation now
      exposes `POST_ALLOW_DETACHED_CODEX_WAKE=false` with the watcher active.

## Permit detached Codex mail wake on Thelio (2026-09-03)

- [x] Pin UNIX MAIL REDUX's safe-by-default detached-Codex wake option, enable
      it only on Thelio under Peter's explicit emailed risk acceptance, prove
      the effective host configuration, and activate without a reboot.
      - Curiosity poke: preserve the attached-client veto. The accepted risk is
        the measured Codex turn interruption after the helper client detaches,
        not permission to type into a session Peter is actively using.
      Completed 2026-09-03 17:33 EDT. The effective 11-assertion host contract,
      complete 11-file configuration suite, privileged dry activation, and
      live switch pass. The watcher is active with the explicit opt-in, and no
      reboot was required. A new detached email remains the upstream project's
      final end-to-end test.

## Temporarily trust Peter-addressed unsigned mail (2026-09-03)

- [x] Opt the Thelio into UNIX MAIL REDUX's explicit final-lap authority policy,
      pin the first implementation that states the exact trusted address in
      fixed wake messages, and prove the effective value before activation.
      - Curiosity poke: an ordinary `From` header and Peter's familiar phone
        signature are both forgeable; the reusable module must remain
        safe-by-default and the live exception must be easy to remove.
      Completed 2026-09-03 16:41 EDT. The 10-assertion host contract, complete
      repository suite, upstream 19-check flake, isolated NixOS mail VM, and
      root-authorized Thelio dry activation all pass. No reboot is required.

## Remove Rust package deprecation warnings (2026-08-28)

- [x] Reproduce and trace `buildFeatures` and `buildNoDefaultFeatures` warnings
      to the responsible flake/package, then add a warning-free evaluation
      regression before replacing them with `withFeatures` and
      `withNoDefaultFeatures`.
      - Curiosity poke: the deprecated arguments do not occur in this repo, so
        the source may be a pinned input whose override must remain updateable.
      Completed 2026-08-28 08:57 EDT: Nix's warning debugger traced both to
      the separately pinned upstream Himalaya flake. The host's current
      Nixpkgs now supplies Himalaya 2.0.0, so the obsolete six-node input was
      removed in favor of `pkgs.himalaya`. A four-assertion regression and an
      uncached full-host evaluation prove both warnings are gone.

## Activate UNIX MAIL REDUX on Thelio (2026-08-28)

- [x] Add a failing effective-configuration contract for Peter's private mail
      domain, Thelio's MagicDNS certificate name, and conservative fleet wake
      policy; then wire the pinned public flake module into the Thelio host.
      Completed 2026-08-28 08:04 EDT: the RED run failed 8/8 assertions before
      the input/module existed, then the exact same contract passed 8/8.
      - Curiosity poke: a successful option evaluation does not prove that the
        certificate can be issued or that Mail.app can authenticate.
- [x] Run the complete configuration suite, build the exact Thelio closure,
      inspect a root-authorized dry activation, and give Peter the no-reboot
      switch command.
      Completed 2026-08-28 08:11 EDT: all 10 test files passed, candidate
      `/nix/store/ycdx0kwsy9r3w02c93hag77gp95j9qzj-nixos-system-thelio-nixos-26.11.20260807.f13ff45`
      built, and dry activation reported only the expected Ops/Polkit/Accounts
      restarts plus firewall reload. The same candidate also vendors the green
      Mechatron remoter namespace fix from source commit `9064957`.
- [x] After activation, verify credentials, TLS, SMTPS-to-LMTP-to-Maildir
      delivery, IMAPS retrieval, `post` on PATH, and the wake service.
      - Live delivery and retrieval passed at 08:40 EDT. The watcher then found
        a missing absolute tmux path; source commit `a8b9912` contains the
        RED/GREEN-tested repair.
      Completed 2026-08-28 09:04 EDT: generation
      `/nix/store/9p38x7g0rhkz103ignc6174p6q0b8wsm-nixos-system-thelio-nixos-26.11.20260807.f13ff45`
      is live. An authenticated message traversed SMTPS, Postfix, LMTP,
      Maildir, and IMAPS; the installed CLI retrieved it; and a second live
      proof made the watcher identify and notify the mixed-case `~/Code`
      Einstein pane. All credential/key modes and four services were verified.

## Package TMog for every x86_64 Nix host (2026-08-26)

- [x] Add a failing contract for a pinned official TMog AppImage package,
      flake-lock-driven update inputs, a non-GUI smoke check, and installation
      in Thelio, Framework, and Tiki-WSL's actual package configurations.
      Completed 2026-08-26 19:33 EDT: the RED run failed all 5 assertions
      before the package, inputs, check, and per-user host placements existed.
      - Curiosity poke: the free Linux build has no updater, and the upstream
        filenames are mutable; lock the raw artifact and version endpoints so
        `nix flake update` refreshes them while normal builds remain pure.
- [x] Implement the minimum AppImage wrapper with desktop/icon integration,
      mark the proprietary beta license accurately, and make the contract pass.
      Completed 2026-08-26 19:33 EDT: the first package smoke build rejected
      the AppImage's wrong inner desktop file; copying the canonical top-level
      desktop entry made the smoke check and complete 9-file suite pass.
      - Curiosity poke: TMog forbids public redistribution, so do not describe
        the package as redistributable or publish its binary through public CI.
- [x] Build the package and all three host closures, then dry-activate Thelio
      and inspect the activation diff before the planned reboot.
      Completed 2026-08-26 19:33 EDT: the package check plus Thelio, Framework,
      and Tiki-WSL closures built. Root-authorized dry activation selected
      `b1j6lydq6bk2wb0qp8212002i1s00ghx` and reported no activation errors.
      - Curiosity poke: GUI execution needs a live display; the sandbox check
        should inspect the packaged executable and metadata rather than pretend
        that a headless launch proves the application renders correctly.

## Make Zed the declarative Markdown editor (2026-08-26)

- [x] Add an effective-flake regression for both Markdown MIME names, observe
  GNOME Builder or an empty mapping fail, then declare Zed through NixOS's
  native `xdg.mime.defaultApplications` option without Home Manager.
  Completed 2026-08-26 10:15 EDT: the RED run passed evaluation but failed both
  empty MIME mappings; the GREEN run passed 3/3 with
  `dev.zed.Zed.desktop` declared for both types.
  - Curiosity poke: MIME databases use both `text/markdown` and the legacy
    `text/x-markdown`; declaring only the type observed today leaves another
    desktop or file classifier able to reopen Builder.
- [x] Pass the complete suite, build and dry-activate the Thelio candidate.
  Completed 2026-08-26 10:18 EDT: all eight test files passed; candidate
  `dxbypgxr4cssza5692887wmh7s9sc6kb` contains the exact two-entry MIME file;
  dry activation reports no service restarts.
- [x] Commit and push the candidate, verify remote equality, and require exact
  Mechatron success.
  Completed 2026-08-26 10:44 EDT: commit `46a4e96` matched `origin/yolo` and
  passed all six exact Mechatron targets in 1,519 seconds. The extended duration
  came from repopulating the garbage-collected Framework closure; the worker
  advanced normally through Framework, Tiki WSL, and the three package checks.

## Stop Mechatron evaluation from churning HDD-backed swap (2026-08-21)

- [x] Add an effective-flake regression for the worker's evaluator memory and
  swap limits, observe the current 512 MiB / 1 GiB / unlimited-swap policy
  fail, then give evaluation enough RAM without relaxing nix-daemon's separate
  builder limits.
  Completed 2026-08-21 16:37 EDT: the RED run passed only evaluation and failed
  all three limit assertions. The GREEN run passed 4/4 with `MemoryHigh=8G`,
  `MemoryMax=12G`, and `MemorySwapMax=1G`; the complete seven-file suite passed.
  - Curiosity poke: the worker is orchestration-only after evaluation begins,
    but `nix build` evaluates the flake in the client process before daemon
    builders take over; the two cgroups need different measured budgets.
- [x] Build the complete host closure and dry-activate the candidate without
  changing the live generation.
  Completed 2026-08-21 16:38 EDT: candidate
  `h7zx5w9n1xr4xnfci6wlxivn7336912v` built successfully and dry activation
  reported only the expected Mechatron worker restart.
- [x] Commit and push the known-good candidate, then require exact-commit
  Mechatron success before activation.
  Completed 2026-08-21 16:52 EDT: commit `bf4c307` passed exact Mechatron CI
  in 75 seconds. The evaluator peaked at about 2.91 GiB of cgroup RAM with zero
  swap; the prior 512 MiB-throttled docs-only run took 514 seconds and pushed
  about 2.6 GiB into swap. The repair made this run 6.85 times faster.
  - Curiosity poke: the current worker has already swapped about 2.6 GiB and
    may need to finish or be restarted before it can validate its own repair.
    Answered: the old run finished before the temporary thresholds changed;
    the next exact run used 2.91 GiB RAM, zero swap, and completed normally.

## Restore Thelio `/tmp` to tmpfs (2026-08-21)

- [x] Establish whether tmpfs was intended here or only remembered from the
  Framework host. Completed 2026-08-21 15:41 EDT: Thelio declared
  `tmpOnTmpfs = true` until commit `c384a4d5` changed it to false on
  2023-01-30 inside an unrelated broad PipeWire/package-stability commit. No
  commit body, inline comment, Git note, or nearby tmpfs commit explains the
  change. Framework has never declared the option.
- [x] Add an effective-flake regression test, observe it fail only on
  `useTmpfs`, restore the setting, and pass the complete configuration suite.
  Completed 2026-08-21 15:47 EDT: the red run passed 3/4 assertions and failed
  the mount contract; the green run passed 4/4, and the six-file repository
  suite passed with zero failures.
  - Curiosity poke answered: the test evaluates `path:/etc/nixos` rather than
    grepping source, so another module cannot silently override the setting and
    untracked TDD edits remain visible to Nix.
- [x] Build and dry-activate the candidate generation, commit and push it.
  Completed 2026-08-21 15:58 EDT: candidate
  `wv6w13a6vryacfvx9bp8nd7b8s0ra8rp` passed the complete build and dry
  activation; commit `a5800ee` matches `origin/yolo` and passed all six exact
  Mechatron targets in 213 seconds.
- [ ] Reboot to mount tmpfs without hiding live agents' existing `/tmp` files.
  After reboot, prove `findmnt -T /tmp` reports tmpfs and rerun the regression.
  - Curiosity poke: keep giant generated AV fixture corpora on
    `/mnt/devcache`; the 20% tmpfs ceiling is 25.6 GB and must not become an
    invitation for a single test to exhaust RAM.

## Standalone Terminal Browser (2026-08-20)

- [x] Verify the terminal dependency from upstream v0.5.8 source rather than
  inferring it from Terminal Code behavior. Completed 2026-08-20 19:34 EDT:
  Terminal Browser renders through the Kitty graphics protocol and ships
  explicit WezTerm and tmux adapters; SSH degrades from file/shared-memory
  frames to compressed inline frames when necessary. Ghostty is recommended,
  not required.
  - Curiosity poke answered: when tmux is present it intentionally wins
    detection over WezTerm, enables passthrough/focus/CSI-u, and wraps each
    graphics command for tmux. A generic `TERM=tmux-256color` is expected.
- [x] Package the official Terminal Browser 0.5.8 x86_64 Linux release from its
  GitHub asset and published SHA-256, refuse its curl-to-shell self-updater,
  expose package and smoke-check outputs, and install it only for Peter.
  Completed 2026-08-20 19:34 EDT: package contract 6/6, complete repository
  suite, all-system flake evaluation, exact host build, and dry activation pass.
- [x] Activate and test the complete human/agent path under WezTerm plus tmux.
  Completed 2026-08-20 19:34 EDT without reboot: a live `example.com` browser
  reported a 1342x1276 viewport; the CLI returned its accessibility tree and
  DOM, produced an inspectable annotated 1332x1238 screenshot, and shutdown
  removed its daemon, browser process, and temporary pane.
  - Curiosity poke answered: this gives agents semantic DOM/accessibility
    inspection, CDP actions, and pixels through screenshots. It is useful
    browser vision, not a general-purpose view into unrelated GUI windows.

## Repair Tode startup on immutable Nix storage (2026-08-20)

- [x] Reproduce ordinary startup's attempt to rewrite the vendored
  `terminal-browser` launcher in `/nix/store` with a package-output contract.
  Curiosity poke: `--version` bypasses runtime resolution, so a version-only
  smoke test can remain green while every useful invocation fails.
  Completed 2026-08-20 15:41 EDT: both new assertions failed against the live
  payload, proving its resolver called `writeLauncher(VENDORED)` and its stored
  launcher lacked the four mutable browser-home overrides.
- [x] Preserve Tode's isolated browser XDG directories without copying the
  bundled browser tree into mutable user storage, then run the complete package
  and system gates. Curiosity poke: the repair must honor existing
  `TODE_BROWSER_*` overrides and must never hardcode Peter's home directory.
  Completed 2026-08-20 15:45 EDT: the built launcher selects absolute XDG homes
  at runtime, honors all four overrides, and creates their directories. The
  focused 7/7 test, complete suite, all-system flake check, Tode smoke check,
  and Thelio system build passed.
- [x] Dry-activate, switch, and manually verify Tode starts from an ordinary
  project directory without an immutable-store error. No reboot should be needed.
  Completed 2026-08-20 15:49 EDT: dry activation required no service changes;
  the switch updated Peter's user profile; and a dedicated tmux smoke from
  `sctui_rust` started code-server, the injector, terminal-browser, and its
  browser daemon without EROFS. `tode --shutdown` removed every smoke process.
  No reboot is required.

## Reconcile local and remote configuration (2026-08-20)

- [x] Merge the three remote-only Tiki, Tailscale, and cosmocc commits with the
  eleven local-only Thelio, Codex, Terminal Code, and Mechatron commits without
  dropping either side. Curiosity poke: compare candidate and committed tree
  objects so a clean textual merge cannot hide an omitted file.
  Completed 2026-08-20 14:29 EDT: commit `3a9391c` merged cleanly after the
  complete suite, flake check, all three host builds, and a Thelio dry activation.
- [x] Add an exact five-output Mechatron manifest and canonical badge, then
  prove every target evaluates and builds. Curiosity poke: CI must build the
  intended host closures instead of guessing a convenient default package.
  Completed 2026-08-20 14:34 EDT in commit `ddf385b`; the manifest gate passed,
  exposing a separate worker-only Git PATH failure during the Thelio build.
- [x] Vendor and activate the upstream Mechatron worker PATH repair, then require
  the pushed `nix_machine_configs` commit to pass all five targets on Mechatron.
  Curiosity poke: interactive Git availability is irrelevant to an isolated
  systemd service, so inspect the generated and live unit environments.
  Completed 2026-08-20 14:48 EDT: upstream commit `46cab0f` passed its own CI;
  config commit `1f2fa32` was dry-activated, switched, and passed all five exact
  targets. The live worker PATH contains Git 2.55.0, and Tailscale remained online.

## Install Terminal Code through Nix (2026-08-20)

- [x] Replace the upstream `curl -fsSL https://tode.sh/install | bash` path
  with a hash-pinned package for Terminal Code 0.1.13 and its required
  code-server 4.132.0 runtime. Do not execute the installer or defer the
  code-server download to first launch. Curiosity poke: the top-level installer
  verifies its own tarball, but the application otherwise downloads a second
  239 MB version-specific workbench after installation.
  Completed 2026-08-20 12:08 EDT: both official GitHub release assets use their
  published SHA-256 digests; the vendored Electron/native payload runs in a
  Nix-built FHS environment.
- [x] Keep update inspection available while making package ownership explicit:
  `--upgrade --check` may query upstream, but mutable self-upgrade and uninstall
  must fail with `/etc/nixos` instructions. Install `tode` only in Peter's user
  package set. Curiosity poke: a Nix-store install whose bundled updater deletes
  user state before failing on the immutable program tree is worse than an
  early, explicit refusal.
  Completed 2026-08-20 12:08 EDT: isolated-home probes returned v0.1.13 and
  witnessed both mutation commands fail before touching state; the full suite
  passed 22/22 assertions and `nix flake check --all-systems` passed.
- [x] Activate the built Thelio generation, verify `tode` from Peter's live
  profile and its desktop entry, then record the generation and commit. No
  reboot should be required. Curiosity poke: a successful package check does
  not prove the per-user profile symlink switched to the candidate generation.
  Completed 2026-08-20 12:13 EDT: privileged dry activation passed before the
  real switch; live generation `12g364rayalp52i0kk3c1ik48iqknhxq` exposes
  `/etc/profiles/per-user/pmarreck/bin/tode`, reports v0.1.13, and provides the
  Terminal Code desktop entry. No reboot was required.

## Activate Codex Linux GUI for Peter (2026-08-15)

- [x] Add an evaluated package-placement contract requiring `codex-app` in
  Peter's NixOS user packages and forbidding it from the global system package
  set. Curiosity poke: a textual assertion could pass while the evaluated host
  omits the package, so inspect the complete evaluated package sets.
  Completed 2026-08-15 15:09 EDT: the new sixth assertion failed against the
  prior host, then passed only after evaluating `codex-app` in Peter's complete
  user package set and outside the complete global package set.
- [x] Activate the existing pinned Codex GUI derivation for `pmarreck`, rebuild
  `/etc/nixos#thelio-nixos`, and verify its executable and desktop entry from
  the live generation. Curiosity poke: activation must preserve the existing
  `~/.codex` conversation and authentication state rather than creating an
  isolated profile.
  Completed 2026-08-15 16:44 EDT: live generation
  `xzyh99q054x8dxdzcsniyn19cl5nz3dk` exposes `chatgpt` and its desktop entry
  from `/etc/profiles/per-user/pmarreck`; the executable reports
  `26.810.41047`. The existing `~/.codex` directory retained inode `25868`.
- [x] Update the package guide, run the full suite and package smoke check, then
  commit the known-good configuration.
  Completed 2026-08-15 16:44 EDT: all 17 repository assertions and the isolated
  package smoke check passed from clean commit `0e686a0`; the clean full-system
  build exactly matched the active generation.

## Ollama Muse-Glimmer support (2026-08-14)

- [x] Advance Peter's Ollama fork to 0.32.13 and llama.cpp b10380 while
  preserving the parallel-embedding scheduler change and deterministic CUDA
  toolkit root. Completed 2026-08-14 15:57 EDT after the local flake check
  built the CUDA runner and passed Ollama's Go test phase.
  - Curiosity poke answered: Ollama 0.32.0 could inspect the GGUF but its older
    llama.cpp runner rejected the new `muse-glimmer` architecture at load time.
- [x] Pin the Thelio flake to fork commit `72b64762`, build the complete system
  generation from the immutable GitHub source, and activate it without a
  reboot. Completed 2026-08-14 16:11 EDT; `ollama.service` restarted healthy as
  `0.32.13-pmarreck.1` with CUDA compute capability 8.6 detected.
  - Curiosity poke answered: the final system build repeated the package build
    because the immutable GitHub source has a distinct Nix identity from the
    local checkout; both candidates passed independently.
- [x] Prove `muse-glimmer-30b-heretic:IQ2_M` through a typed fleet-summary
  contract, then unload it from the GPU. Completed 2026-08-14 16:24 EDT; fixed
  seed plus JSON Schema reproduced every scalar exactly at 3.67 tokens/s.
  - Curiosity poke answered: GGUF imported under Ollama 0.32.0 carried an
    invalid `<|message|>` stop and no Glimmer renderer/parser. The stable local
    manifest explicitly sets `renderer=glimmer`, `parser=glimmer`, `<|eot|>`
    stops, and reuses the original model/projector blobs without duplication.

## Codex Linux GUI package (2026-08-14)

- [x] Add a failing package contract for an x86_64 Linux derivation sourced
  from OpenAI's official `.deb`: fixed version/hash, desktop/icon payload,
  executable closure, and no vendor APT maintainer scripts. Curiosity poke:
  Electron's sandbox and bundled updater may assume a mutable FHS install even
  when every ELF dependency is patched.
  Completed 2026-08-14 13:59 EDT: the five-assertion contract first failed 0/4,
  then gained and witnessed the deprecated-X11-name failure before passing 5/5.
- [x] Implement the smallest standalone Nix package, expose it as a flake
  package/check, build it, and run a noninteractive launch smoke test without
  adding it to the Thelio system profile. Curiosity poke: a successful
  `autoPatchelfHook` pass does not prove GPU/Wayland startup or prevent a hidden
  self-update path from writing into `/nix/store`.
  Completed 2026-08-14 13:59 EDT: the official payload runs unchanged in a
  Nix-built FHS environment; the sandboxed check invokes the launcher and
  requires exact version `26.810.41047`. The 3.0 GiB closure is not activated.
- [x] Document the verified architecture and usage, update dirtree notes, run
  `./test` plus the package check, then commit the known-good package.
  Completed 2026-08-14 13:59 EDT: 16 repository assertions, package build,
  sandboxed launch check, and full `nix flake check --no-build` pass.
- [x] Publish the exact derivation and guide as a public GitHub gist, verify its
  local and remote bytes, then email Peter both mutable and immutable gist URLs.
  Completed 2026-08-14 14:01 EDT: cloned and byte-compared gist
  `ff5cc10a6b15ca1e01b0d0901c0e365c`; emailed its friendly and immutable
  revision URLs to `peter@marreck.com` from the connected Gmail account.

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
