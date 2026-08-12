# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

# { config, pkgs, nixpkgs, stable, unstable, trunk, lib, home-manager, nixos-hardware, ... }:
# `inputs` + `system` are injected via flake specialArgs (see /etc/nixos/flake.nix) — replaces
# the old <nixos-unstable>/<nixos-master> NIX_PATH channel lookups. `system` is threaded to each
# scope `import` because pure flake eval has no `builtins.currentSystem`. Migrated to flake 2026-07-05.
{ options, config, pkgs, lib, inputs, system, ... }:
# add unstable channel definition for select packages, with unfree permitted
# Note that prior to this working you need to run:
# sudo nix-channel --add https://nixos.org/channels/nixos-unstable nixos-unstable
# to add to global channels and for user channels run
# nix-channel --add https://nixos.org/channels/nixos-unstable nixos-unstable
# for hardware-specific packages
# sudo nix-channel --add https://github.com/NixOS/nixos-hardware/archive/master.tar.gz nixos-hardware
# sudo nix-channel --update

# ❯ sudo nix-channel --list
# nixos https://nixos.org/channels/nixos-unstable
# nixos-hardware https://github.com/NixOS/nixos-hardware/archive/master.tar.gz
# nixos-master https://github.com/NixOS/nixpkgs/archive/master.tar.gz
# nixos-stable https://nixos.org/channels/nixos-22.11
# nixos-unstable https://nixos.org/channels/nixos-unstable

let
  # FYI: My system got switched to unstable,
  # but I left in the unstable scoping for my original "unstable" packages
  # (I don't believe this should cause any problems)
  # and added a "stable" scope for any packages that break in unstable
  # so I can just downgrade them to stable on a case by case basis
  # Shared nixpkgs config for the extra scopes (unstable/stable/master). Each is
  # its own nixpkgs instantiation, so the base `nixpkgs.config` does NOT reach
  # them — insecure/unfree permits must be declared here too. olm is an
  # insecure-but-unavoidable transitive dep of the Matrix clients (stable.nheko,
  # unstable.fluffychat).
  scopeConfig = {
    allowUnfree = true;
    permittedInsecurePackages = [ "olm-3.2.16" ];
  };
  # `unstable` reuses the base flake input (nixos-unstable), instantiated separately with
  # scopeConfig (no overlays) — matches the old `import <nixos-unstable> { config = scopeConfig; }`.
  unstable = import inputs.nixpkgs {
    inherit system;
    config = scopeConfig;
    # overlays = [
    # # use native cpu optimizations
    # # note: NOT PURE
    #   (self: super: {
    #     stdenv = super.impureUseNativeOptimizations super.stdenv;
    #   })
    # ];
  };
  # `stable` now follows the flake input `nixpkgs-2605` (release-26.05 branch — see
  # /etc/nixos/flake.nix); `nix flake update` / `ixnay reify --upgrade` rolls it. This
  # supersedes the previous in-config tarball pin (rev 721be26… release-26.05). Serves
  # stable.limo (mod manager) plus stable.cudaPackages / stable.ripgrep-all.
  stable = import inputs.nixpkgs-2605 { inherit system; config = scopeConfig; };
  # `master` scope dropped 2026-07-05 during the flake migration — on an unstable base it
  # bought little and risked eval breakage. Its former refs now use `unstable.*`.
  # my custom proprietary fonts
  key-rebel-moon = pkgs.callPackage ./key-rebel-moon.nix { };
  tech-alive = pkgs.callPackage ./tech-alive.nix { };
  # Official prebuilt Cosmopolitan toolchain from cosmo.zip — see the doc
  # comment in ../cosmocc-bin.nix for why we don't use nixpkgs' cosmocc
  # (stale 2.2 + its from-source test suite fails on ZFS roots like this one).
  cosmocc-bin = pkgs.callPackage ../cosmocc-bin.nix { };
  # which particular version of elixir and erlang I want globally
  erlang = unstable.erlang; # I like to live dangerously. For fallback, use stable of: # erlangR25;
  elixir = pkgs.beam.packages.erlangR26.elixir_1_15;
  # libretro = stable.libretro;
  # `comma` (run any nixpkgs program without installing) is packaged in nixpkgs itself now, so
  # use pkgs.comma directly. The old GitHub import (nix-community/comma v1.6.0) was a flake-compat
  # shim relying on impure eval (`builtins.currentSystem`); it broke under pure flake eval with
  # "attribute 'default' missing". Now tracks the maintained nixpkgs build. 2026-07-05 flake migration.
  comma = pkgs.comma;
  # nix-software-center = (import (pkgs.fetchFromGitHub {
  #   owner = "vlinkz";
  #   repo = "nix-software-center";
  #   rev = "0.1.1";
  #   sha256 = "0frigabszyfkphfbsniaa1d546zm8a2gx0cqvk2fr2qfa71kd41n";
  # })) {};
  # custom_python3 = ((pkgs.python310.override {
  #     enableOptimizations = true;
  #     reproducibleBuild = false;
  #     # self = custom_python3;
  #   }).withPackages (ps: with ps; [
  #   (zfec.overrideAttrs (old: {
  #     src = /home/pmarreck/Documents/zfec;
  #   }))
  #   pip
  #   toolz
  #   requests # for requests
  #   pillow  # for image processing
  #   virtualenv
  #   pytest # for testing
  #   pandas # for data analysis
  #   urllib3 # for requests
  #   nltk  # natural language toolkit
  #   torch # for machine learning
  #   torchvision
  #   torchaudio-bin
  #   sentencepiece
  #   numpy
  # ])).override (args: { ignoreCollisions = true; });
in
{
  imports =
    [ # See the following on how to convert this to flakes or add the channel:
      # https://github.com/NixOS/nixos-hardware
      # <nixos-hardware/system76>
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./zfs.nix
      ./ollama.nix   # local inference backend for codescan (Ollama-CUDA, 2× NVIDIA) — Einstein 2026-07-07
      ./mechatron-prime-attic.nix   # tailnet-local binary cache for Mechatron Prime CI — Codex 2026-07-08
      ./mechatron-prime-receiver.nix   # GitHub webhook receiver for Mechatron Prime CI — Codex 2026-07-08
      ./mechatron-prime-worker.nix   # queue worker for Mechatron Prime CI — Codex 2026-07-08
      ./mechatron-prime-ops.nix   # tailnet-only host operations console and FSearch timer — Codex 2026-07-11
      ./accentd.nix   # macOS-style press-and-hold accent popup (evdev/uinput + GTK4) — Einstein 2026-07-28
      ./rotational-io.nix   # bfq + deeper queues for the USB-docked spinning rpool; Klipsch name fix — Einstein 2026-07-28
      # home-manager.nixosModule
      # <nixos-unstable/nixos/modules/services/monitoring/netdata.nix>
    ];

  # Overlays
  nixpkgs.overlays = [
    # use native cpu optimizations
    # note: NOT PURE
    # (self: super: {
    #   stdenv = super.impureUseNativeOptimizations super.stdenv;
    # })
    # Firefox Nightly
    (import ./firefox-overlay.nix)
    (import ./packages)
  ];

  # Any temporarily-allowed insecure packages.
  nixpkgs.config.permittedInsecurePackages = [
    "xrdp-0.9.9" # added 1/5/2023
    "mailspring-1.11.0" # added 10/9/2023
    "olm-3.2.16" # added 2026-07-02 — transitive dep of nheko/fluffychat (Matrix); olm is deprecated-but-unavoidable for those clients until they move to vodozemac
  ];

  # Early console config. Note: Replaced by kmscon
  # console = {
  #   font = "ter-132n";
  #   packages = [pkgs.terminus_font];
  #   # keyMap = "us"; # inherited from x11 layout, below, I believe
  #   useXkbConfig = true;
  #   earlySetup = false;
  # };

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n = {
    defaultLocale = "en_US.UTF-8";
  };
  # Bootloader.
  boot = {
    tmp = {
      useTmpfs = false;
      tmpfsSize = "20%"; # of 128GB = 25.6GB
      cleanOnBoot = true;
    };
    crashDump.enable = true;
    # NFS client support: pulls in nfs-utils so `mount.nfs` exists. Without it,
    # `mount -t nfs` (e.g. the `nas` helper) falls back to the in-kernel
    # fsconfig() API and dies with "NFS: mount program didn't pass remote
    # address". This is the userland mount helper, NOT a server. (nixpkgs
    # nfs.nix: supportedFilesystems.nfs => system.fsPackages = [ nfs-utils ].)
    supportedFilesystems = [ "nfs" ];
    loader = {
      ## I switched from systemd-boot to grub2 when I figured out how to get onto zfs root,
      ## and the defaults seemed to work fine, don't know enough about boot/EFI yet to mess with it
      # systemd-boot.enable = false;
      grub = {
        # version = 2; # removed based on deprecation warning
        enable = true;
        efiSupport = true;
        # the grub init tune doesn't actually work on my hardware but is supposedly Super Mario?
        extraConfig = ''
          GRUB_GFXMODE=3440x1440x32,auto
          GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=2"
          GRUB_GFXPAYLOAD_LINUX="keep"
          GRUB_INIT_TUNE="1750 523 1 392 1 523 1 659 1 784 1 1047 1 784 1 415 1 523 1 622 1 831 1 622 1 831 1 1046 1 1244 1 1661 1 1244 1 466 1 587 1 698 1 932 1 1195 1 1397 1 1865 1 1397 1"
        '';
        configurationLimit = 10; # default is like 100? Too much
        theme = pkgs.fetchFromGitHub { # current as of 11/2022
          owner = "shvchk";
          repo = "fallout-grub-theme";
          rev = "fcc680d166fa2a723365004df4b8736359d15a62";
          sha256 = "sha256-7kvLfD6Nz4cEMrmCA9yq4enyqVyqiTkVZV5y4RyUatU=";
        };
      };
      # efi.canTouchEfiVariables = true; # zfs config specifies false, so...
      # efi.efiSysMountPoint = "/boot/efi";
      # swraid.enable = false; # due to a bug, this defaulted to true, see: https://github.com/NixOS/nixpkgs/issues/254807
    };
    ${if options.boot ? swraid then "swraid" else null} = {
      enable = false;
    };
    # Boot using the latest kernel: pkgs.linuxPackages_latest
    # Boot with bcachefs test: pkgs.linuxPackages_testing_bcachefs
    # TODO: investigate zen kernel
    # Commented out to use stable for now :/
    # kernelPackages = pkgs.linuxPackages_latest; #pkgs.linuxPackages_rpi4;
    # kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages; # for latest zfs-compatible kernel

    hardwareScan = true; # tried to make udev run faster at boot by falsing, but then my keyboard and mouse stopped working lol (usb driver not loaded, perhaps?)

    kernel.sysctl = {
      # 2026-07-30: 40 -> 10. Swap lives on /dev/sdd4 — a 7200rpm USB-docked
      # spinning drive (~20 ms/seek), the SLOWEST device in the machine. At 40,
      # 17.2 GB had been evicted there: gnome-shell 766 MB, Firefox content
      # processes 600-680 MB each, ghostty 424 MB. Touching an idle tab then
      # paid ~100k page-ins at 20 ms — the "tabs take forever to load" symptom.
      #
      # Aggravated by ZFS: ARC sat at 46.7 of its 48 GiB cap, and ARC reclaims
      # far more slowly than the page cache under pressure, so the kernel
      # evicted APPLICATION pages instead of shrinking ARC. 10 tells it to
      # reclaim cache/ARC first. Deliberately NOT lowering zfs_arc_max — that
      # 48 GiB was raised from 16 GiB in b26ef2e to fix dnode-cache thrash
      # (8h+ of arc_prune CPU); cutting it would reintroduce that.
      #
      # 2026-07-31: 10 -> 50, now that swap lives on NVMe (nvme0n1p3) instead of
      # the USB-docked spinning drives. A deliberate compromise, not the full 60:
      # 10 was correct for ~20 ms swap, but on fast swap it is over-conservative
      # — suppressing swap that hard pushes reclaim pressure onto the ZFS ARC
      # instead, and ARC reclaim churn is precisely what generated the bogus
      # per-cgroup PSI readings that made systemd-oomd kill 19 MB cgroups.
      # 50 lets the kernel use cheap NVMe paging again without swinging all the
      # way back to the default. Revisit with evidence, one variable at a time.
      "vm.swappiness" = 50; # 90 when swapping to ssd; default is 60
      "vm.vfs_cache_pressure" = 80; # default is 100
      "vm.dirty_ratio" = 60; # https://sites.google.com/site/sumeetsingh993/home/experiments/dirty-ratio-and-dirty-background-ratio
      "vm.max_map_count" = 16777216; # literally based on a recommendation for the game Hogwarts Legacy to crash less
      "vm.dirty_background_ratio" = 20;
      "kernel.task_delayacct" = 1; # so iotop/iotop-c can work; may add latency
      "kernel.sched_latency_ns" = 4000000;
      "kernel.sched_min_granularity_ns" = 500000;
      "kernel.sched_wakeup_granularity_ns" = 50000;
      "kernel.sched_migration_cost_ns" = 250000;
      "kernel.sched_cfs_bandwidth_slice_us" = 3000;
      "kernel.sched_nr_migrate" = 128;
      "kernel.sysrq" = 1; # enables the very special sysrq key combo https://en.wikipedia.org/wiki/Magic_SysRq_key
    };

    kernelParams = [ "quiet"
                     "splash"
                     "boot.shell_on_fail"
                     "cgroup_no_v1=all"
                     "loglevel=2"
                     "rd.udev.log_level=2"
                     "udev.log_priority=2"
                     "nvidia_drm.modeset=1"
                     # ┌─ GPU-HIDE TOGGLE (Darktide / dual-GPU XWayland fix) ─────────────┐
                     # │ Hides the RTX 2080 Ti (PCI 21:00.0, vendor:device 10de:1e07) from │
                     # │ the nvidia driver by handing it to pci_stub at boot. WHY: with    │
                     # │ BOTH NVIDIA GPUs visible under GNOME 50 / Wayland, vkd3d-proton    │
                     # │ logs "DXGI: monitors not associated with any adapter, using       │
                     # │ fallback" (x17) and then "Surface is not supported for            │
                     # │ presentation" -> swapchain create fails -> Darktide crashes at    │
                     # │ startup. The monitor lives on the 3080 Ti (10de:2208); with two   │
                     # │ adapters present, DXGI can't prove which one owns the surface.    │
                     # │ Collapsing to a single visible GPU removes the ambiguity. This    │
                     # │ worked implicitly on real Xorg in 2023 (single-adapter path).     │
                     # │ COST: the 2080 Ti is unavailable for compute/offload while this   │
                     # │ line is active. Pairs with pci_stub in initrd.kernelModules above │
                     # │ (which must load FIRST). Comment this line out to restore the     │
                     # │ 2080 Ti for compute. The 3080 Ti device-id is 10de:2208 (do NOT   │
                     # │ stub that one — it drives the display).                           │
                     # └───────────────────────────────────────────────────────────────────┘
                     "pci-stub.ids=10de:1e07"
                     "video=3440x1440@100" # for virtual console resolution
                     "systemd.unified_cgroup_hierarchy=yes"
                     "systemd.gpt_auto=0" # so that systemd doesn't try to mount my zfs root before zfs is loaded
                     "scsi_mod.use_blk_mq=1" # https://www.kernel.org/doc/html/latest/block/blk-mq.html
                     "elevator=bfq" # https://wiki.archlinux.org/title/Improving_performance#BFQ_I/O_scheduler
                     "zfs.l2arc_noprefetch=1"
                     "zfs.l2arc_write_boost=16777216"
                     "zfs.l2arc_write_max=16777216"
                     "zfs.l2arc_headroom=2"
                     "zfs.l2arc_mfuonly=0"
                     "zfs.zfs_arc_max=51539607552" # 48GB (was 16GB; see dnode note below)
                     # dnode cache defaults to 10% of arc_max. With /nix, / and devpool
                     # on ZFS the dnode working set is huge (millions of small files), so
                     # a 16GB arc gave a 1.6GB dnode budget that sat pegged at 97.6% —
                     # 38M cumulative arc_prune calls and 8h+ of arc_prune CPU over one
                     # 3-day uptime. 48GB arc + 25% gives a 12GB dnode budget (13% used).
                     "zfs.zfs_arc_dnode_limit_percent=25"
                     # rpool (/, /home, /var) is a 7200rpm mirror behind a USB dock, so
                     # every txg commit costs full-stroke seeks to rewrite uberblocks at
                     # the labels on both ends of the platter. At the 5s default that is a
                     # seek storm every 5 seconds forever — audible as continuous clicking
                     # even at ~0% utilisation, and it starves interactive reads.
                     # 15s means a third as many commits, each larger. Raise further only
                     # with eyes open: this is the window of writes lost on a hard power
                     # cut (ZIL still protects anything fsync'd). Peter, 2026-07-28.
                     "zfs.zfs_txg_timeout=15"
                     # 2026-07-31: was `zfs.prefetch_disable=1` — a TYPO that
                     # silently did nothing. The module parameter is
                     # `zfs_prefetch_disable`; `prefetch_disable` does not
                     # exist, so the kernel ignored it. Confirmed by
                     # /sys/module/zfs/parameters/zfs_prefetch_disable reading
                     # 0 (i.e. prefetch ENABLED) despite this line. Note the
                     # working ARC lines above use the same shape —
                     # `zfs.zfs_arc_max` — where `zfs.` is the module and
                     # `zfs_arc_max` is the real parameter name.
                     #
                     # Intent (rpool is 34% fragmented on USB-docked spinning
                     # disks, and the workload is not large sequential files):
                     # speculative prefetch there costs seeks for data that is
                     # often not used.
                     #
                     # CAVEAT: this now actually takes effect at next boot, so
                     # it IS a live behaviour change after years of being inert.
                     # ARC hit rate is already 99.6%, so most reads never reach
                     # a disk — the win may be small. If anything regresses,
                     # revert this one line (or write 0 to
                     # /sys/module/zfs/parameters/zfs_prefetch_disable at
                     # runtime, no reboot needed).
                     "zfs.zfs_prefetch_disable=1"
                    #  "spl_taskq_thread_dynamic=0" # attempt to fix continuous spawn of runaway z_wr_iss/z_wr_int processes during nixos builds
                    #  EDIT: I believe I fixed the runaway z_wr_iss/z_wr_int process spawn issue just by reverting to lz4 compression for now
                    #  "zfs.l2arc_rebuild_enabled=1" # may be the default now, but why not be explicit?
                    #  "zfs.l2arc_mfuonly=1" # only l2arc-cache most frequently used data, not most recently used data
                   ];
    consoleLogLevel = 2;

    # for fancy boot/loading screen, because duh
    # took this from a collection at: https://github.com/adi1090x/plymouth-themes
    # unfortunately, it only lasts for a second or 2...
    plymouth = {
      enable = true;
      themePackages = [ pkgs.adi1090x-plymouth ];
      theme = "metal_ball";
    };

    # modules to load early in the boot process, for nicer boot splash at correct rez
    initrd = {
      verbose = false;
      # NOTE: pci_stub is listed FIRST on purpose. It pairs with the
      # "pci-stub.ids=10de:1e07" kernelParam below (the GPU-HIDE TOGGLE) and must
      # claim the 2080 Ti before the nvidia driver probes it, or nvidia wins the
      # race and the device stays visible. Order in this list = load order.
      # Harmless when the pci-stub.ids param is absent (pci_stub just claims nothing).
      kernelModules = [ "pci_stub" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
    };

    # this may fix some zfs issues, but with something so important, caveat emptor
    # zfs.enableUnstable = true;
    # l2arc_write_boost=16777216; # 32mb/s (max+boost vals) boost speed before ARC is full, default is 8mb/s
    # l2arc_write_max=16777216; # 16mb/s, default is 8mb/s
    # regarding ZFS tunables:
    # https://forums.freebsd.org/threads/howto-tuning-l2arc-in-zfs.29907/
    # https://nixos.wiki/wiki/ZFS
    # https://wiki.freebsd.org/ZFSTuningGuide
    # Good l2arc docs: https://klarasystems.com/articles/openzfs-all-about-l2arc/
    # https://openzfs.github.io/openzfs-docs/man/4/zfs.4.html
    extraModprobeConfig = ''
      options zfs l2arc_noprefetch=1 \
      l2arc_write_boost=16777216 \
      l2arc_write_max=16777216 \
      l2arc_headroom=2 \
      l2arc_mfuonly=0 \
      zfs_arc_max=51539607552 \
      zfs_arc_dnode_limit_percent=25 \
      zfs_txg_timeout=15 \
      zfs_prefetch_disable=1
    '';
  };

  # Networking details
  networking = {
    hostName = "thelio-nixos"; # Define your hostname.
    # Enable networking
    # Pick only one of the below networking options.
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    networkmanager.enable = true; # Easiest to use and most distros use this by default.
    # Configure network proxy if necessary
    #   proxy.default = "http://user:password@proxy:port/";
    #   proxy.noProxy = "127.0.0.1,localhost,internal.domain";
    # Boot optimizations regarding networking:
    # don't wait for an ip before proceeding with boot
    dhcpcd.wait = "background";
    # don't check and wait to see if IP is already taken by another device on the network
    dhcpcd.extraConfig = "noarp";
    # fix for https://github.com/NixOS/nix/issues/5441
    # hosts = {
    #   "127.0.0.1" = [ "this.pre-initializes.the.dns.resolvers.invalid." ];
    # };
    # nameservers = [
    #   "192.168.7.234" # my pihole
    #   "1.1.1.1"
    # ];
    # stuff to go in /etc/hosts
    # extraHosts = ''
    #   192.168.2.1    genera-vlm
    #   192.168.2.2    genera
    # '';
  };

  systemd = {
    # Shutdown was hanging ~90s on a stuck unit, tempting a hard power-off (bad on
    # a ZFS root). Drop the default stop timeout so a wedged unit is force-killed
    # after 30s instead of 90s. Per-unit TimeoutStopSec / infinity still override.
    # Applies on next rebuild + reboot. (If a hang recurs, read the console line
    # "A stop job is running for <unit>" — that names the culprit to fix at root.)
    # NB: nixpkgs-unstable removed `systemd.extraConfig`; use settings.Manager.
    settings.Manager.DefaultTimeoutStopSec = "30s";

    # systemd-oomd DISABLED (Peter, 2026-07-31) — it was killing healthy
    # processes based on a sensor this machine cannot report honestly.
    #
    # Evidence, 2026-07-31 14:04-14:06 (`journalctl -b -u systemd-oomd`): it
    # marked and killed FOUR cgroups whose reported "Current Memory Usage" was
    # 18.4 MB and 19.5 MB — on a 125 GiB machine with ~74 GiB available —
    # solely because per-cgroup PSI memory pressure read 92-99%, over the
    # 60%-for-30s default trigger. There were ZERO kernel OOM-killer entries:
    # the machine was never actually out of memory. And because oomd kills
    # whole CGROUPS, and the tmux server lived inside a ghostty surface scope,
    # EVERY tmux session on the box died at once. Cost: ~3 hours of work time.
    #
    # Root cause of the false signal: ZFS ARC at its 48 GiB cap drives
    # continuous reclaim, which gets attributed as per-cgroup memory pressure.
    # PSI is independently known-unreliable on this host — /proc/pressure/io
    # reads ~97% while both disks measure 0% busy. (Third metric this machine
    # invalidates, all ZFS-related: iowait, /proc/pressure/*, /proc/PID/io.)
    #
    # Safe because: 125 GiB RAM, and the KERNEL OOM killer remains as the real
    # backstop — it acts on actual allocation failure rather than on a pressure
    # estimate. In its present state oomd could only ever produce false kills.
    #
    # Revisit if PSI ever becomes trustworthy under ZFS; until then this is a
    # sensor problem, not a policy problem.
    oomd.enable = false;
    user = {
      services = {
        # GNOME's LocalSearch/Tracker successor crawls and extracts metadata from
        # home-directory files. Keep file indexing explicit or scheduled instead.
        "localsearch-3".enable = false;
        "localsearch-control-3".enable = false;
        "localsearch-writeback-3".enable = false;

        # my custom grandfather clock gong script
        clocksound = let
          # Vendored 2026-07-05 from the pinned gist permalink to make this pure/self-contained
          # under flake eval (was `builtins.readFile (builtins.fetchurl scriptUrl)` — an eval-time
          # network fetch that breaks pure eval). Source gist:
          # https://gist.github.com/pmarreck/2a2de1a5227383625829fdaf9b50c4a3
          # Refresh by re-fetching the raw gist into ./clocksound.bash.
          scriptContent = builtins.readFile ./clocksound.bash;
          scriptFile = pkgs.writeShellScriptBin "clocksound" ''
            export PATH="${pkgs.mpv}/bin:$PATH"
            ${scriptContent}
          '';
        in {
          description = "Play grandfather clock sound on the hour";
          serviceConfig = {
            ExecStart = "${scriptFile}/bin/clocksound";
            Type = "oneshot";
          };
        };
        # Run RescueTime for all users
        rescuetime = {
          description = "RescueTime time tracker";
          partOf = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          serviceConfig = {
            ExecStart = "${pkgs.rescuetime}/bin/rescuetime";
          };
        };
      };
      timers = {
        clocksound = {
          description = "Run clocksound.service on the hour";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = [
              "*-*-* 07..23:00:00"
              "*-*-* 00:00:00"
            ];
            Unit = "clocksound.service";
            # Persistent = true;
          };
        };
      };
    };
    services = {
      # some of these things were tweaked to speed up booting.
      # See output of: systemd-analyze blame
      # 2026-07-26: RE-ENABLED. This mask is why there were no persistent logs
      # since 2022-09-06 — a masked flush can never copy /run/log/journal to
      # /var/log/journal, so journald stayed volatile every boot regardless of
      # Storage=. The 2026-07-25 root-pool incident therefore left no forensic
      # trail at all.
      # The original reason is obsolete: jbd2 is the EXT4 journaling daemon, and
      # this host has a ZFS root (rpool/nixos/var/log is its own dataset), so the
      # high-disk-utilization failure mode it worked around cannot occur here.
      # Flush cost is now bounded by SystemMaxUse=1G in journald.extraConfig.
      # If boot time regresses noticeably, lower that bound rather than
      # re-masking and going blind again.
      systemd-journal-flush.enable = true;
      # note that the following may cause zfs pools not to mount, even though it shouldn't;
      # please see discussion @ https://github.com/openzfs/zfs/issues/10891
      # systemd-udev-settle.enable = false; # speed up booting
      NetworkManager-wait-online.enable = false; # speed up booting
      # more booting speedup... for the next 2 lines, see: https://github.com/NixOS/nixpkgs/issues/41055
      modem-manager.enable = false;
      "dbus-org.freedesktop.ModemManager1".enable = false;
      # ── Envelope so a CI build cannot starve the desktop ────────────────
      # Peter, 2026-07-31: "Kicking off a CI build shouldn't completely slam my
      # machine." Correct — and the fix is NOT where it looks.
      #
      # MEASURED (nixos-perf-review, during a live `nix build`): the Mechatron
      # worker shells out to ordinary `nix build`, and the multi-user Nix
      # daemon creates the builders — /proc/PID/cgroup placed the build shell
      # and `make -j8` under /system.slice/nix-daemon.service, NOT the worker's
      # cgroup. Limits on the worker unit would therefore constrain only its
      # bash/jq orchestration and do NOTHING to the compilers. The envelope
      # belongs here.
      #
      # Weights alone (what this block used to be) only help when a sibling
      # cgroup is already contending; they never stop Nix occupying all 128
      # threads when capacity is free. Host: 128 logical / 64 physical CPUs,
      # nix max-jobs=16 x cores=8 = 128 nominal, previously CPUQuota=infinity,
      # MemoryMax=infinity, TasksMax=1048576 — no ceiling at all.
      #
      # NB: these apply to ALL Nix builds, including Peter's manual ones.
      nix-daemon.serviceConfig = {
        # 80 of 128 logical CPUs. Deliberately ABOVE the 64-CPU scheduler
        # target so a derivation that oversubscribes (nix `cores` is advisory,
        # not enforced) still cannot take the box, while reserving ~48 CPUs
        # for the desktop.
        CPUQuota = "8000%";
        CPUWeight = 25; # was 50; yield harder to interactive work
        Nice = 10;
        # MemoryHigh is the throttle intended to bite; MemoryMax is the last
        # line of defence. Observed daemon peak since boot was 16.7 GB, so
        # there is substantial headroom.
        MemoryHigh = "48G";
        MemoryMax = "64G";
        MemorySwapMax = "8G";
        # Defence-in-depth only — ZFS cgroup I/O attribution is not trusted on
        # this host (same reason PSI is unusable here).
        IOWeight = 25; # was 50
        TasksMax = 8192;
      };

      # ORCHESTRATION ONLY — explicitly NOT a build cap; see the note above.
      # Documented loudly so nobody later mistakes this for the thing that
      # limits compilers. Measured worker peak: 284 MB.
      mechatron-prime-worker.serviceConfig = {
        CPUQuota = "200%";
        CPUWeight = 25;
        Nice = 10;
        MemoryHigh = "512M";
        MemoryMax = "1G";
        IOWeight = 25;
        TasksMax = 512;
      };
      # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
      "getty@tty1".enable = false;
      "autovt@tty1".enable = false;
    };
    # https://discourse.nixos.org/t/desktop-oriented-kernel-scheduler/12588/3
    # migrated from systemd.extraConfig (removed) to systemd.settings.Manager
    settings.Manager = {
      DefaultCPUAccounting = true;
      DefaultMemoryAccounting = true;
      DefaultIOAccounting = true;
    };
    # the following doesn't seem to do anything but add extra duplicate lines to /etc/systemd/system.conf
    # user.extraConfig = ''
    #   DefaultCPUAccounting=yes
    #   DefaultMemoryAccounting=yes
    #   DefaultIOAccounting=yes
    # '';
    # note: this is a literal "user@"; not, say, "pmarreck@"
    # check with: systemctl show user-1000.slice
    # These don't seem to have an effect, but leaving here for now
    services."user@".serviceConfig.Delegate = true;
    services."user@".serviceConfig.LimitNOFILE = 9001; # because "over 9000!", duh
  };

  # Allow unfree packages (necessary for firefox and steam etc)
  nixpkgs.config = {
    allowUnfree = true;
    # allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    #   "steam"
    #   "steam-original"
    #   "steam-runtime"
    # ];
    # packageOverrides = pkgs: {
    #   inherit (unstable) netdata;
    # };
    # for some reason this chromium config no longer works (seen in a 2018 configuration.nix):
    # chromium = {
    #   enablePepperFlash = true;
    #   enablePepperPDF = true;
    #   # enableWideVine = true;
    # };
  };

  # build for this CPU! (Ryzen Threadripper 3990x)
  # ...This didn't work.
  # nixpkgs.localSystem = {
  #   gcc.arch = "native"; # "znver2";
  #   gcc.tune = "native";
  #   system = "x86_64-linux";
  # };

  # List services that you want to enable:
  services = {

    gnome.gnome-remote-desktop.enable = true; # because it inadvertently activates pipewire... which is fine now


    # Enable the much fancier kmscon virtual console instead of gettys.
    # ...I'm not actually sure if this is working as advertised. Needs to be tested.
    kmscon = {
      enable = true;
      config.hwaccel = true; # was services.kmscon.hwRender (renamed to config.hwaccel)
      # `autologinUser` removed -> moved to services.getty.autologinUser below.
      # `fonts` list removed -> font set via config.font-name (install fonts via fonts.packages if you want this exact one).
      config.font-name = "Terminus NerdFont";
      extraOptions = "--term xterm-256color --font-size 12";
    };
    getty.autologinUser = "pmarreck"; # replaces removed services.kmscon.autologinUser

    # Enable the X11 windowing system.
    xserver = {
      enable = true;
      # wayland wonky with nvidia, still — but disabling gdm.wayland is unsupported with GNOME 50 (option removed)
      # displayManager.gdm.wayland = false;
      # use nvidia card for xserver
      videoDrivers = ["nvidia"];
      # Configure keymap in X11 (renamed: services.xserver.xkb.*)
      xkb.options = "mod_led:compose,compose:ralt,terminate:ctrl_alt_bksp,shift:breaks_caps";
      xkb.layout = "us";
      xkb.variant = "";
      # Enable touchpad support (enabled default in most desktopManager).
      # libinput.enable = true;
      # try out windowmaker!
      # windowManager.windowmaker.enable = true;
      # displayManager.defaultSession = "none+windowmaker";
    };

    # Display & desktop managers were renamed OUT of services.xserver.* in
    # nixpkgs: services.xserver.displayManager.* -> services.displayManager.*,
    # and services.xserver.desktopManager.gnome -> services.desktopManager.gnome.
    # Enable GDM + the GNOME Desktop Environment.
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
    # Enable automatic login for the user.
    displayManager.autoLogin.enable = false;
    # if above is true, you'd still need to unlock the keyring anyway and sometimes that modal dialog gets stuck, forcing a reboot
    displayManager.autoLogin.user = "pmarreck";
    # Reinstate the minimize/maximize buttons!
    # To list all possible settings, try this:
    # > gsettings list-schemas
    # then pick one and use it here:
    # > gsettings list-recursively <schema-name>
    # Try to keep the settings groups in alphabetical order.
    desktopManager.gnome.extraGSettingsOverrides = ''
      [org.gnome.desktop.interface]
      text-scaling-factor=1.25

      [org.gnome.desktop.wm.preferences]
      button-layout=':minimize,maximize,close'
      resize-with-right-button=true

      [org.gnome.nautilus.preferences]
      always-use-location-entry=true

      [org.gnome.settings-daemon.plugins.color]
      night-light-enabled=true
      night-light-temperature=2500
      night-light-schedule-automatic=true

      [org.gnome.SessionManager]
      auto-save-session=true

      [org.gtk.Settings.FileChooser]
      sort-directories-first=false
    '';
      # mouse-button-modifier='<Alt>'

    # Enable CUPS to print documents.
    printing.enable = true;

    # Enable sound with pipewire.
    pipewire = {
      enable = true;
      # wireplumber and media-session are mutually exclusive
      # EDIT: media-session no longer supported on pipewire and removed upstream as of 2023-03-27
      wireplumber.enable = true;
      # media-session.enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      # If you want to use JACK applications, uncomment this
      jack.enable = true;

      # use the example session manager (no others are packaged yet so this is enabled by default,
      # no need to redefine it in your config for now)
      #media-session.enable = true;
      # Disabled config.pipewire based on this warning on update (2023-03-27):
      #  - The option definition `services.pipewire.config' in `/etc/nixos/configuration.nix' no longer has any effect; please remove it.
      #  Overriding default Pipewire configuration through NixOS options never worked correctly and is no longer supported.
      #  Please create drop-in files in /etc/pipewire/pipewire.conf.d/ to make the desired setting changes instead.
      # config.pipewire = {
      #   "context.properties" = {
      #     "link.max-buffers" = 32;
      #     # "link.max-buffers" = 16; # version < 3 clients can't handle more than this
      #     "log.level" = 2; # https://docs.pipewire.org/page_daemon.html
      #     "default.clock.rate" = 48000;
      #     "default.clock.quantum" = 64;
      #     "default.clock.min-quantum" = 32;
      #     "default.clock.max-quantum" = 128;
      #     "core.daemon" = true;
      #     "core.name" = "pipewire-0";
      #   };
      #   "context.modules" = [
      #     {
      #       name = "libpipewire-module-rtkit";
      #       args = {
      #         "nice.level" = -15;
      #         "rt.prio" = 88;
      #         "rt.time.soft" = 200000;
      #         "rt.time.hard" = 200000;
      #       };
      #       flags = [ "ifexists" "nofail" ];
      #     }
      #     { name = "libpipewire-module-protocol-native"; }
      #     { name = "libpipewire-module-profiler"; }
      #     { name = "libpipewire-module-metadata"; }
      #     { name = "libpipewire-module-spa-device-factory"; }
      #     { name = "libpipewire-module-spa-node-factory"; }
      #     { name = "libpipewire-module-client-node"; }
      #     { name = "libpipewire-module-client-device"; }
      #     {
      #       name = "libpipewire-module-portal";
      #       flags = [ "ifexists" "nofail" ];
      #     }
      #     {
      #       name = "libpipewire-module-access";
      #       args = {};
      #     }
      #     { name = "libpipewire-module-adapter"; }
      #     { name = "libpipewire-module-link-factory"; }
      #     { name = "libpipewire-module-session-manager"; }
      #   ];
      # };
      # media-session.config.bluez-monitor.rules = [
      #   {
      #     # Matches all cards
      #     matches = [ { "device.name" = "~bluez_card.*"; } ];
      #     actions = {
      #       "update-props" = {
      #         "bluez5.reconnect-profiles" = [ "hfp_hf" "hsp_hs" "a2dp_sink" ];
      #         # mSBC is not expected to work on all headset + adapter combinations.
      #         "bluez5.msbc-support" = true;
      #         # SBC-XQ is not expected to work on all headset + adapter combinations.
      #         "bluez5.sbc-xq-support" = true;
      #       };
      #     };
      #   }
      #   {
      #     matches = [
      #       # Matches all sources
      #       { "node.name" = "~bluez_input.*"; }
      #       # Matches all outputs
      #       { "node.name" = "~bluez_output.*"; }
      #     ];
      #   }
      # ];
    };

    # Boot optimizations regarding filesystem:
    # 2026-07-26: Storage was "auto", which SILENTLY overrode NixOS's own
    # Storage=persistent default (systemd takes the LAST occurrence of a key).
    # Consequence: the newest entry in /var/log/journal was 2022-09-06 — nearly
    # four years with no persistent logs, so the 2026-07-25 root-pool dropout
    # left no forensic trail at all. Under "auto", journald only uses
    # /var/log/journal if it already exists when journald starts; on ZFS root the
    # /var dataset mounts later, so it stayed volatile forever.
    #
    # The original reason for "auto" was slow boot while flushing runtime logs to
    # disk. Mitigated by bounding the journal hard (was 300M x 50 = 15G ceiling)
    # so each flush stays small. If boot regresses noticeably, lower SystemMaxUse
    # further rather than returning to "auto" and going blind again.
    journald.extraConfig = ''
      Storage=persistent
      SystemMaxUse=1G
      SystemMaxFileSize=64M
      SystemMaxFiles=16
    '';

    # screensaver config
    # seems to only work when home manager is present. commenting out here, try again later
    #  xscreensaver = {
    #    enable = true;
    #    settings = {
    #      timeout = 2;
    #      lock = false;
    #      fadeTicks = 60;
    #      mode = "random";
    #    };
    #  };

    # Enable the OpenSSH daemon.
    openssh.enable = true;

    # gnome daemons
    udev.packages = with pkgs; [ gnome-settings-daemon ];

    # RDP
    xrdp.enable = true;

    # Postgres
    # disabled here and enabled at project level for now
    # postgresql = {
    #   enable = true;
    #   package = pkgs.postgresql_13;
    #   enableTCPIP = true;
    #   authentication = pkgs.lib.mkOverride 10 ''
    #     local all all trust
    #     host all all 127.0.0.1/32 trust
    #     host all all ::1/128 trust
    #   '';
    #   initialScript = pkgs.writeText "backend-initScript" ''
    #     CREATE ROLE postgres WITH LOGIN PASSWORD 'postgres' CREATEDB;
    #     CREATE DATABASE postgres;
    #     CREATE DATABASE mpnetwork;
    #     GRANT ALL PRIVILEGES ON DATABASE postgres TO postgres;
    #     GRANT ALL PRIVILEGES ON DATABASE mpnetwork TO postgres;
    #   '';
    # };

    # Netdata
    # netdata = {
    #   enable = true; # might be already declared by the import above
    # };

    # Samba
    samba = {
      enable = true;
      winbindd.enable = true; # was services.samba.enableWinbindd (renamed)
      # migrated from services.samba.extraConfig (removed) to services.samba.settings
      settings = {
        global = {
          "workgroup" = "WORKGROUP";
          "server string" = "Samba Server %v";
          "netbios name" = "nixos";
          "security" = "user";
          "map to guest" = "bad user";
          "dns proxy" = "no";
          "bind interfaces only" = "yes";
          "interfaces" = "lo enp68s0 wlo2 wlp69s0";
          "log file" = "/var/log/samba/log.%m";
          "max log size" = 1000;
          "syslog" = 0;
          "panic action" = "/usr/share/samba/panic-action %d";
          "server role" = "standalone server";
          "passdb backend" = "tdbsam";
          "obey pam restrictions" = "yes";
          "unix password sync" = "yes";
          "passwd program" = "/usr/bin/passwd %u";
          "passwd chat" = ''*Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .'';
          "pam password change" = "yes";
          "usershare allow guests" = "yes";
        };
        "homes" = {
          "comment" = "Home Directories";
          "browseable" = "no";
          "read only" = "no";
          "create mask" = "0700";
          "directory mask" = "0700";
          "valid users" = "%S";
        };
        "printers" = {
          "comment" = "All Printers";
          "browseable" = "no";
          "path" = "/var/spool/samba";
          "printable" = "yes";
          "guest ok" = "no";
          "read only" = "yes";
          "create mask" = "0700";
        };
        "print$" = {
          "comment" = "Printer Drivers";
          "path" = "/var/lib/samba/printers";
          "browseable" = "yes";
          "read only" = "yes";
          "guest ok" = "no";
        };
      };
    };

    # Fartpak
    flatpak.enable = true;

    # ZFS, yeah, baby, yeah!!
    zfs = {
      autoScrub = {
        enable = true;
        # First MONDAY of the month at 00:00, instead of the NixOS default
        # "monthly" (which is *-*-01 00:00 -- the 1st, whatever weekday that is).
        # Peter, 2026-08-01, after the 1st landed on a Saturday and a ~9h rpool
        # scrub collided with a working day.
        #
        # Monday 00:00 rather than Sunday 00:00 because "Sunday night" in the
        # colloquial sense IS Monday morning once the clock passes midnight;
        # Sunday 00:00 would actually be Saturday night.
        #
        # `Mon *-*-01..07` is the systemd idiom for "first Monday": exactly one
        # Monday can fall within days 1-7. Verified with
        #   systemd-analyze calendar "Mon *-*-01..07 00:00:00" --iterations=6
        # -> 2026-08-03, 09-07, 10-05, 11-02, 12-07, 2027-01-04. All first Mondays.
        #
        # Note rpool lives on the two USB-docked spinning drives, so its scrub
        # takes ~9 hours and is felt; the NVMe pools finish in seconds to minutes.
        interval = "Mon *-*-01..07 00:00:00";
      };
      trim.enable = true;
    };

    # Various controller udev rules stolen from https://gitlab.com/fabiscafe/game-devices-udev
    # TODO: Move this the hell out of this file somehow
    udev.extraRules = ''
      # 8Bitdo F30 P1
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo FC30 GamePad", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8Bitdo F30 P2
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo FC30 II", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8Bitdo N30
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo NES30 GamePad", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8Bitdo SF30
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo SFC30 GamePad", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8Bitdo SN30
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo SNES30 GamePad", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8Bitdo F30 Pro
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo FC30 Pro", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8Bitdo N30 Pro
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo NES30 Pro", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8Bitdo SF30 Pro
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo SF30 Pro", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8Bitdo SN30 Pro
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo SN30 Pro", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8BitDo SN30 Pro+; Bluetooth; USB
      SUBSYSTEM=="input", ATTRS{name}=="8BitDo SN30 Pro+", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo SF30 Pro   8BitDo SN30 Pro+", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8Bitdo F30 Arcade
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo Joy", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8Bitdo N30 Arcade
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo NES30 Arcade", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8Bitdo ZERO
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo Zero GamePad", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8Bitdo Retro-Bit xRB8-64
      SUBSYSTEM=="input", ATTRS{name}=="8Bitdo N64 GamePad", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # 8BitDo Pro 2; Bluetooth; USB
      SUBSYSTEM=="input", ATTRS{name}=="8BitDo Pro 2", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      SUBSYSTEM=="input", ATTR{id/vendor}=="2dc8", ATTR{id/product}=="6003", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # Alpha Imaging Technology Corp.
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="114d", ATTRS{idProduct}=="8a12", TAG+="uaccess"
      # ASTRO Gaming C40 Controller; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="9886", ATTRS{idProduct}=="0025", MODE="0660", TAG+="uaccess"
      # Betop PS4 Fun Controller
      KERNEL=="hidraw*", ATTRS{idVendor}=="11c0", ATTRS{idProduct}=="4001", MODE="0660", TAG+="uaccess"
      # Hori RAP4
      KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="008a", MODE="0660", TAG+="uaccess"
      # Hori HORIPAD 4 FPS
      KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="0055", MODE="0660", TAG+="uaccess"
      # Hori HORIPAD 4 FPS Plus
      KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="0066", MODE="0660", TAG+="uaccess"
      # Hori HORIPAD S; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="00c1", MODE="0660", TAG+="uaccess"
      # Hori Nintendo Switch HORIPAD Wired Controller; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0f0d", ATTRS{idProduct}=="00c1", MODE="0660", TAG+="uaccess"
      # HTC
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="2c87", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="0306", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="0309", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="030a", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="030b", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="030c", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="030e", TAG+="uaccess"
      # HTC VIVE Cosmos; USB; https://gitlab.com/fabis_cafe/game-devices-udev/-/issues/1/ #EXPERIMENTAL
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0bb4", ATTRS{idProduct}=="0313", TAG+="uaccess"
      SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="0315", MODE="0660", TAG+="uaccess"
      SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="0323", MODE="0660", TAG+="uaccess"
      # Logitech F310 Gamepad; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c216", MODE="0660", TAG+="uaccess"
      # Logitech F710 Wireless Gamepad; USB #EXPERIMENTAL
      KERNEL=="hidraw*", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c21f", MODE="0660", TAG+="uaccess"
      # Mad Catz Street Fighter V Arcade FightPad PRO
      KERNEL=="hidraw*", ATTRS{idVendor}=="0738", ATTRS{idProduct}=="8250", MODE="0660", TAG+="uaccess"
      # Mad Catz Street Fighter V Arcade FightStick TE S+
      KERNEL=="hidraw*", ATTRS{idVendor}=="0738", ATTRS{idProduct}=="8384", MODE="0660", TAG+="uaccess"
      # Microsoft Xbox360 Controller; USB #EXPERIMENTAL
      SUBSYSTEM=="usb", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="028e", MODE="0660", TAG+="uaccess"
      SUBSYSTEMS=="input", ATTRS{name}=="Microsoft X-Box 360 pad", MODE="0660", TAG+="uaccess"
      # Microsoft Xbox 360 Wireless Receiver for Windows; USB
      SUBSYSTEM=="usb", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="0719", MODE="0660", TAG+="uaccess"
      SUBSYSTEMS=="input", ATTRS{name}=="Xbox 360 Wireless Receiver", MODE="0660", TAG+="uaccess"
      # Microsoft Xbox One S Controller; bluetooth; USB #EXPERIMENTAL
      KERNEL=="hidraw*", KERNELS=="*045e:02ea*", MODE="0660", TAG+="uaccess"
      SUBSYSTEMS=="usb", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="02ea", MODE="0660", TAG+="uaccess"
      # Nacon PS4 Revolution Pro Controller
      KERNEL=="hidraw*", ATTRS{idVendor}=="146b", ATTRS{idProduct}=="0d01", MODE="0660", TAG+="uaccess"
      # Nintendo Switch Pro Controller; bluetooth; USB
      KERNEL=="hidraw*", KERNELS=="*057E:2009*", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="2009", MODE="0660", TAG+="uaccess"
      # Nintendo GameCube Controller / Adapter; USB
      SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="0337", MODE="0660", TAG+="uaccess"
      # NVIDIA Shield Portable (2013 - NVIDIA_Controller_v01.01 - In-Home Streaming only)
      KERNEL=="hidraw*", ATTRS{idVendor}=="0955", ATTRS{idProduct}=="7203", ENV{ID_INPUT_JOYSTICK}="1", ENV{ID_INPUT_MOUSE}="", MODE="0660", TAG+="uaccess"
      # NVIDIA Shield Controller (2017 - NVIDIA_Controller_v01.04); bluetooth
      KERNEL=="hidraw*", KERNELS=="*0955:7214*", MODE="0660", TAG+="uaccess"
      # NVIDIA Shield Controller (2015 - NVIDIA_Controller_v01.03); USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0955", ATTRS{idProduct}=="7210", ENV{ID_INPUT_JOYSTICK}="1", ENV{ID_INPUT_MOUSE}="", MODE="0660", TAG+="uaccess"
      # PDP Afterglow Deluxe+ Wired Controller; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0e6f", ATTRS{idProduct}=="0188", MODE="0660", TAG+="uaccess"
      # PDP Nintendo Switch Faceoff Wired Pro Controller; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0e6f", ATTRS{idProduct}=="0180", MODE="0660", TAG+="uaccess"
      # PDP Wired Fight Pad Pro for Nintendo Switch; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0e6f", ATTRS{idProduct}=="0185", MODE="0666", TAG+="uaccess"
      # Personal Communication Systems, Inc. Twin USB Gamepad; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0810", ATTRS{idProduct}=="e301", MODE="0660", TAG+="uaccess"
      SUBSYSTEM=="input", ATTRS{name}=="Twin USB Gamepad*", ENV{ID_INPUT_JOYSTICK}="1", TAG+="uaccess"
      # PowerA Wired Controller for Nintendo Switch; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="20d6", ATTRS{idProduct}=="a711", MODE="0660", TAG+="uaccess"
      # PowerA Zelda Wired Controller for Nintendo Switch; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="20d6", ATTRS{idProduct}=="a713", MODE="0660", TAG+="uaccess"
      # PowerA Wireless Controller for Nintendo Switch; bluetooth
      # We have to use ATTRS{name} since VID/PID are reported as zeros.
      # We use sh instead of udevadm directly becuase we need to
      # use '*' glob at the end of "hidraw" name since we don't know the index it'd have.
      # Thanks @https://github.com/ValveSoftware
      # KERNEL=="input*", ATTRS{name}=="Lic Pro Controller", RUN{program}+="sh -c 'udevadm test-builtin uaccess /sys/%p/../../hidraw/hidraw*'"
      # Razer Raiju PS4 Controller
      KERNEL=="hidraw*", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="1000", MODE="0660", TAG+="uaccess"
      # Razer Panthera Arcade Stick
      KERNEL=="hidraw*", ATTRS{idVendor}=="1532", ATTRS{idProduct}=="0401", MODE="0660", TAG+="uaccess"
      # Sony PlayStation Strikepack; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c5", MODE="0660", TAG+="uaccess"
      # Sony PlayStation DualShock 3; bluetooth; USB
      KERNEL=="hidraw*", KERNELS=="*054C:0268*", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0268", MODE="0660", TAG+="uaccess"
      ## Motion Sensors
      SUBSYSTEM=="input", KERNEL=="event*|input*", KERNELS=="*054C:0268*", TAG+="uaccess"
      # Sony PlayStation DualShock 4; bluetooth; USB
      KERNEL=="hidraw*", KERNELS=="*054C:05C4*", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0660", TAG+="uaccess"
      # Sony PlayStation DualShock 4 Slim; bluetooth; USB
      KERNEL=="hidraw*", KERNELS=="*054C:09CC*", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0660", TAG+="uaccess"
      # Sony PlayStation DualShock 4 Wireless Adapter; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ba0", MODE="0660", TAG+="uaccess"
      # Sony DualSense Wireless-Controller; bluetooth; USB
      KERNEL=="hidraw*", KERNELS=="*054C:0CE6*", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", TAG+="uaccess"
      # PlayStation VR; USB
      SUBSYSTEM=="usb", ATTR{idVendor}=="054c", ATTR{idProduct}=="09af", MODE="0660", TAG+="uaccess"
      # Valve generic(all) USB devices
      SUBSYSTEM=="usb", ATTRS{idVendor}=="28de", MODE="0660", TAG+="uaccess"
      # Valve Steam Controller write access
      KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
      # Valve HID devices; bluetooth; USB
      KERNEL=="hidraw*", KERNELS=="*28DE:*", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", ATTRS{idVendor}=="28de", MODE="0660", TAG+="uaccess"
      # Valve
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="1043", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="1142", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2000", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2010", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2011", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2012", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2021", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2022", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2050", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2101", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2102", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2150", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2300", MODE="0660", TAG+="uaccess"
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2301", MODE="0660", TAG+="uaccess"
      # Zeroplus(ZP) appears to be a tech-provider for variouse other companies.
      # They all use the ZP ID. Because of this, they are grouped in this rule.
      # Armor PS4 Armor 3 Pad; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0c12", ATTRS{idProduct}=="0e10", MODE="0660", TAG+="uaccess"
      # EMiO PS4 Elite Controller; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0c12", ATTRS{idProduct}=="1cf6", MODE="0660", TAG+="uaccess"
      # Hit Box Arcade HIT BOX PS4/PC version; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0c12", ATTRS{idProduct}=="0ef6", MODE="0660", TAG+="uaccess"
      # Nyko Xbox Controller; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0c12", ATTRS{idProduct}=="8801", MODE="0660", TAG+="uaccess"
      # Unknown-Brand Xbox Controller; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0c12", ATTRS{idProduct}=="8802", MODE="0660", TAG+="uaccess"
      # Unknown-Brand Xbox Controller; USB
      KERNEL=="hidraw*", ATTRS{idVendor}=="0c12", ATTRS{idProduct}=="8810", MODE="0660", TAG+="uaccess"
      # PS5 DualSense controller over USB hidraw
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", TAG+="uaccess"
      # PS5 DualSense controller over bluetooth hidraw
      KERNEL=="hidraw*", KERNELS=="*054C:0CE6*", MODE="0660", TAG+="uaccess"
    '';
  };

  # Configure my 3D card correctly (hopefully!)
  # ...Actually, simply setting config.programs.steam.enable = true does these:
  # hardware.opengl = {
  #   enable = true;
  #   # see discussion: https://app.bountysource.com/issues/74599012-nixos-don-t-set-ld_library_path-for-graphics-drivers-that-don-t-need-it
  #   # setLdLibraryPath = true;
  #   driSupport32Bit = true;
  # };
  # possible options for the following: https://discourse.nixos.org/t/solved-what-are-the-options-for-hardware-nvidia-package-docs-seem-out-of-date/14251
  # Rolled beta(595.45.04) -> production(595.80) 2026-06-22 to test whether the beta
  # driver regressed NVIDIA Vulkan XWayland surface presentation (Darktide
  # "Surface is not supported for presentation"). production is newer AND keeps both GPUs.
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.production; # was .beta (595.45.04); .vulkan_beta also possible
  hardware.nvidia.nvidiaPersistenced = true; # keep /dev/nvidia* alive at boot so GDM stops racing node creation
  hardware.nvidia.open = false; # 24.05+ made this mandatory (no default). false = proprietary kernel module, matches prior behavior on these Turing/Ampere cards.
  services.gnome.gcr-ssh-agent.enable = false; # GNOME now auto-enables a gcr ssh-agent; disable it since programs.ssh.startAgent is on (they conflict)
  services.gnome.localsearch.enable = false; # do not register GNOME's background home-directory indexer

  # Dormant indexed CLI search. Enable later if direct path lookup is needed.
  # /nix/store is intentionally searchable, despite store paths being ephemeral.
  services.locate = {
    enable = false;
    interval = "03:30";
    package = pkgs.plocate;
    prunePaths = [
      "/tmp"
      "/var/tmp"
      "/var/cache"
      "/var/lock"
      "/var/run"
      "/var/spool"
      "/nix/var/log/nix"
      "/home/pmarreck/.local/share/Steam"
      "/home/pmarreck/.local/share/docker"
    ];
  };

  # Tailscale (added 2026-07-02). Mesh VPN / WireGuard. After the first rebuild
  # authenticate once with `sudo tailscale up` (opens a browser login). The
  # `openFirewall` opens the UDP port used for direct (non-DERP-relayed)
  # connections. `useRoutingFeatures = "both"` lets this box act as an exit node
  # AND accept subnet routes; if you only ever use it as a plain client, "client"
  # is enough. To advertise as an exit node: `sudo tailscale up --advertise-exit-node`.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "both";
  };

  services.resolved.enable = true;

  services.displayManager.gdm.autoSuspend = false; # never auto-suspend at the idle login screen (renamed out of services.xserver)
  # hardware.nvidia.powerManagement.enable = true; # should only be used on laptops, maybe?

  # Enable sound with pipewire.
  # sound.enable = true;
  services.pulseaudio.enable = false; # renamed from hardware.pulseaudio in newer nixos
  security.rtkit.enable = true;

  # Enable the OpenRazer driver for my Razer stuff
  hardware.openrazer.enable = true;

  # Enable bluetooth. Wait, this wasn't the default??
  # hardware.bluetooth.enable = true;

  # Define a user account. Set a password hash via `mkpasswd -m sha-512`
  users.mutableUsers = false;
  # user definitions are immutably defined only here
  users.defaultUserShell = pkgs.bash;
  users.users.root = {
    initialHashedPassword = "$6$xLM1UDNfT/H8lbHK$jKAmqDp39Sj7O.ccOAN4tTBVOL4WoD6RaDcWa/Yg1XFE037sAGsN6WL4psvoKnanybrHYDwSFMWzHcCegp2ht0";
    shell = pkgs.bash;
  };
  # users.users.root.hashedPassword = config.users.users.root.initialHashedPassword;
  users.users.pmarreck = {
    isNormalUser = true;
    description = "Peter Marreck";
    # "mechatron-prime" grants read-only diagnostic access to the CI state
    # directory (worker logs, current.json, the result ledger) and to
    # /etc/nix/netrc, so the CI agent can diagnose build failures without a
    # root shell.  Peter authorized this tradeoff on 2026-07-25: it widens who
    # can read CI credentials on this host in exchange for self-service
    # diagnosis.  It deliberately does NOT grant write access to worker state.
    extraGroups = [ "networkmanager" "wheel" "tty" "input" "openrazer" "audio" "plugdev" "kvm" "mechatron-prime" ];
    shell = pkgs.bash;
    hashedPassword = "$6$xLM1UDNfT/H8lbHK$jKAmqDp39Sj7O.ccOAN4tTBVOL4WoD6RaDcWa/Yg1XFE037sAGsN6WL4psvoKnanybrHYDwSFMWzHcCegp2ht0";

    # TODO: move these to home-manager
    packages = with pkgs; [
      # erlang # the inspiration for the best language
      # elixir # the best language
      # ruby # my OG love
      # I added some standard langs and build tools to all envs for now:
      # python3Full # added with an overridden pkg, above
      # nodejs # for javascript spaghetticode
      # pcre # perl-compatible regex
      jdk # java
      openssl # security
      curlpp # for curl bindings in C++
      pkg-config # for compiling C/C++
      gcc # compiler for C
      opencl-clhpp # for opencl
      ocl-icd # for opencl
      patchelf # for fixing up binaries in nix
      stable.cudaPackages.cudatoolkit # for tensorflow
      mono # for C#/.NET stuff
      # unstable.vscode # removed 2026-07-02 — migrated to Zed; VSCode only opened a blank window here anyway
      unstable.gnome-builder # code editor
      unstable.orbiton # Simple text editor/IDE intentionally limited to VT100 (pkg `o` renamed to `orbiton`); https://github.com/xyproto/o
      unstable.micro # sort of an enhanced nano
      unstable.gum # looks like a super cool TUI tool for shell scripts: https://github.com/charmbracelet/gum
      # postgresql # the premier open-source database # we are only using project-based pg's for now
      # asdf-vm # version manager for many languages
      python311Packages.pygments # syntax highlighting for 565 languages in terminal
      conda # python package manager (ew. but need it for LLM's)
      asciinema # record terminal sessions
      glow # markdown viewer
      delta #syntax highlighter for git
      stable.ripgrep-all # ripgrep-all is a wrapper around ripgrep, fd, and git that allows you to search through your codebase using ripgrep syntax.
      parallel # parallelize shell commands
      stable.spotifyd # spotify streamer daemon
      stable.spotify # forced stable on 2/16/2023 due to build failure on unstable
      # spotify-tui # REMOVED from nixpkgs (unmaintained upstream); successor is `spotify-player`
      slack # the chat app du jour
      zoom-us # the chinese spy network
      # matrix clients [
        stable.nheko # matrix client # forced stable on 6/28/2023 due to build failure on unstable
        unstable.fluffychat # re-enabled 4/11/2023 after apparent dependency bugfix
      # ]
      figlet # ascii art
      jq # json query
      fzf # fuzzy finder
      fzy # fuzzy finder that's faster/better than fzf
      broot # TUI-navigable file browser
      peco # TUI fuzzy finder and selector
      fortune # fortune cookie
      taoup # The Tao of Unix Programming
      speedread # speed reading
      speedtest-cli
      # markets # stock market watcher # went defunct in march 2023: https://github.com/tomasz-oponowicz/markets
      ticker # stock market watcher, to replace the "markets" GUI
      qalculate-gtk # very cool calculator
      galculator # calculator GUI
      filezilla # it's no Transmit.app, but it'll do
      rclone # rsync for cloud storage
      rclone-browser # GUI for rclone
      remmina # remote-desktop client (VNC/RDP/SSH/SPICE) — e.g. connect to a Mac's built-in Screen Sharing (VNC) over Tailscale
      rustdesk # modern P2P remote-desktop (own fast codec, clipboard/file xfer) — smoother than VNC for the Mac; ride Tailscale w/ direct connection
      free42 # hp-42S reverse-engineered from the ground up
      # numworks-epsilon # whoa, cool calc! # disabled due to disuse, and troubleshooting an issue
      browsh # graphical web browser in the terminal
      # 2026-07-28: was `unstable.ollama` (STOCK). Replaced with Peter's fork, the
      # same package the ollama.service runs, so exactly ONE ollama implementation
      # exists on this host. Stock cannot serve Jina embeddings — it returns HTTP
      # 501 because it cannot configure Jina's required last-token pooling, which
      # is why the fork exists and why codescan depends on it.
      # A stock binary on PATH is not harmless: on 2026-07-27 one was started by
      # hand, bound 127.0.0.1:11434 against the stale ~/.ollama store, and silently
      # locked out the real service until the process was killed.
      inputs.ollama.packages.${system}.default # llms in the terminal (Peter's fork)
      inputs.himalaya.packages.${system}.default # CLI email client (pimalaya) — v2.0 from upstream flake, since nixpkgs is still 1.2.0; manages both Gmail accounts + composable CLI mail core. Accounts configured per-user in ~/.config/himalaya/, NOT here.
      bluebubbles # iMessage client for Linux (Peter, 2026-07-31). Talks to the BlueBubbles SERVER already installed on his Mac, which relays iMessage — so iMessages reach this Linux dev box. Client only; nothing server-side is configured here.
      darktable # RAW photo processor. Two reasons (Peter, 2026-07-29): (1) a source of real-world RAW/image formats + a reference decoder (rawspeed/libraw) for Mecha Validate's RAW coverage and corruption-detection corpus; (2) scriptable via its built-in Lua API + headless `darktable-cli`, so agents can automate fixture generation / batch conversion. lua-scripts (darktable-org) is a separate optional package if wanted.
      unstable.codex # OpenAI Codex CLI — agentic coding assistant in the terminal (declarative; has a `codex` bash wrapper in dotfiles for yolo mode)
      # mathematica # because why the heck not?
      # actually, NOPE:
      # This nix expression requires that Mathematica_13.0.1_BNDL_LINUX.sh is
      # already part of the store. Find the file on your Mathematica CD
      # and add it to the nix store with nix-store --add-fixed sha256 <FILE>.
      # Awaiting update to 13.1.0:
      # ❯ nix-store --add-fixed sha256 Mathematica_13.1.0_BNDL_LINUX.sh
      # /nix/store/jsnr55faq59xkq1az8isrs9rkzxdpxj2-Mathematica_13.1.0_BNDL_LINUX.sh
      # (the package was updated for 13.1.0)
      blesh # bluetooth shell
      xscreensaver # note that this seems to require setup in home manager
      gthumb # image viewer
      hyperfine # command-line benchmarking tool
      # for desktop gaming
      # simply setting config.programs.steam.enable to true adds stable steam
      stable.heroic # heroic game launcher # forced stable on 4/13/2023 due to build failure on unstable
      # legendary-gl
      stable.rare # rare is a game launcher for epic games store # forced stable on 2/16/2023 due to build failure on unstable
      # lutris # It always struck me as wonky, but I'm including this game launcher for now. EDIT: Nope, still wonky AF. Bye.
      # protonup # automates updating GloriousEggroll's Proton-GE # currently borked, see: https://github.com/AUNaseef/protonup/issues/25
      # proton-caller # REMOVED from nixpkgs (unmaintained upstream)
      # bottles
      # gnutls # possibly needed for bottles to work correctly with battle.net launcher?
      discord # chat app for gamers
      # razergenie # razer mouse/keyboard config tool. disabled because seems lamer than polychromatic
      polychromatic # razer mouse/keyboard config tool
      # whatsapp-for-linux REMOVED from nixpkgs 2026 (unmaintained, archived upstream) during the
      # flake migration. nixpkgs suggests `karere` as a replacement, but that's a DIFFERENT client —
      # left for Peter to choose (adopt karere, or just use web.whatsapp.com). Was: unstable.whatsapp-for-linux
      # unstable.karere # whatsapp desktop client (uncomment to adopt the suggested replacement)
      unstable.signal-desktop # signal desktop client
      telegram-desktop # chat app
      transmission_4-gtk # torrent client (renamed from transmission-gtk in 24.11)
      bfs # better, breadth-first search
      nms # No More Secrets, a recreation of the live decryption effect from the famous hacker movie "Sneakers"
      boinc # distributed computing
      treesheets # freeform data organizer
      flameshot # screenshot tool
      shotwell # photo organizer like iPhoto
      stable.darktable # photo editor # forced stable on 1/24/2023 due to build failure on unstable
      krita # drawing program
      stable.gimp-with-plugins # drawing program # forced stable on 1/20/2023 due to build failure on unstable
      dunst # notification daemon for x11; wayland has "mako"; discord may crash without one of these
      # bluemail # email client # doesn't currently work...
      stable.mailspring # nice open-source email client # forced stable on 6/29/2026: base channel's mailspring 1.22.0 deadlocks at electron-packager during source build (self-pipe hang); stable channel (nixos-26.05) ships 1.21.1 as a cached binary, no source build
      # thunderbird # the venerable email client
      # evolutionWithPlugins # email client
      recoll # full-text search tool
      moor # a better "less" (moar was renamed to moor upstream in v2.0.0)
      stable.sequeler # gui for postgresql/mariadb/mysql/sqlite; very nice # downgraded to stable 6/13/2023 due to build failure on unstable
      jetbrains.datagrip # gui for postgresql/mariadb/mysql/sqlite
      gitkraken # git gui (as opposed to "git gud" I guess)
      starship # cool prompt
      # for retro gaming. this workaround was to fix the cores not installing properly
      # (retroarch.override { cores = with libretro; [
      #   atari800 beetle-gba beetle-lynx beetle-ngp beetle-pce-fast beetle-pcfx beetle-psx beetle-psx-hw beetle-saturn beetle-snes beetle-supergrafx
      #   beetle-vb beetle-wswan bluemsx bsnes-mercury citra desmume desmume2015 dolphin dosbox eightyone fbalpha2012 fbneo fceumm flycast fmsx freeintv
      #   gambatte genesis-plus-gx gpsp gw handy hatari mame mame2000 mame2003 mame2003-plus mame2010 mame2015 mame2016 mesen meteor mgba mupen64plus
      #   neocd nestopia np2kai o2em opera parallel-n64 picodrive play ppsspp prboom prosystem quicknes sameboy scummvm smsplus-gx snes9x
      #   snes9x2002 snes9x2005 snes9x2010 stella stella2014 tgbdual thepowdertoy tic80 vba-m vba-next vecx virtualjaguar yabause
      #   # pcsx-rearmed
      # ]; })
      # retroarch
      # (with libretro; [
      #   atari800 beetle-gba beetle-lynx beetle-ngp beetle-pce-fast beetle-pcfx beetle-psx beetle-psx-hw beetle-saturn beetle-snes beetle-supergrafx
      #   beetle-vb beetle-wswan bluemsx bsnes-mercury citra desmume desmume2015 dolphin dosbox eightyone fbalpha2012 fbneo fceumm flycast fmsx freeintv
      #   gambatte genesis-plus-gx gpsp gw handy hatari mame mame2000 mame2003 mame2003-plus mame2010 mame2015 mame2016 mesen meteor mgba mupen64plus
      #   neocd nestopia np2kai o2em opera parallel-n64 picodrive play ppsspp prboom prosystem quicknes sameboy scummvm smsplus-gx snes9x
      #   snes9x2002 snes9x2005 snes9x2010 stella stella2014 tgbdual thepowdertoy tic80 vba-m vba-next vecx virtualjaguar yabause
      #   # pcsx-rearmed
      # ])
      # TUI and/or RPG games [
        angband # roguelike
        # zangband # error: Package ‘zangband-2.7.4b’ in ... is marked as broken, refusing to evaluate.
        # tome2 # roguelike — DISABLED 2026-07-02: broken across ALL scopes (stable/base 2.4-unstable-2025 snapshot fails on vendored jsoncons; unstable 2.4 fails on std::map/boost-mp11) — old C++ that won't compile under 26.05-era GCC. Re-enable via a stdenv/GCC-downgrade override or a pinned old nixpkgs rev where it last built.
        nethack # roguelike
        unnethack # roguelike
        harmonist # roguelike
        hyperrogue # roguelike
        crawl # roguelike
        crawlTiles # roguelike
        brogue-ce # roguelike (use brogue-ce instead of brogue for updated releases)
        meritous # platformer
        egoboo # dungeon crawler
        sil # roguelike
        shattered-pixel-dungeon # roguelike
      # ]
      # other games & stuff
      xlife # cellular automata
      abuse # classic side-scrolling shooter customizable with LISP
      jazz2 # open source reimplementation of classic Jazz Jackrabbit 2 game
      newtonwars # missile game with gravity as a core element
      # gamehub # REMOVED from nixpkgs (archived upstream, old webkitgtk 4.0)
      gravit # gravity simulator
      xaos # smooth fractal explorer
      almonds # TUI fractal viewer
      scorched3d # played the original version a lot in the military
      pioneer # space exploration game
      the-powder-toy # sandbox game
      space-cadet-pinball # nostalgia
      airshipper # for veloren voxel game
      unvanquished # FPS
      endless-sky # space exploration game
      # tremulous # boooo, marked as broken :(
      torcs # racing game
      stable.speed_dreams
      # littlesnitch fork:
      stable.opensnitch # forced stable on 2/16/2023 due to build failure on unstable
      stable.opensnitch-ui
      # media/video stuff
      audacity # audio editor
      unstable.clementine # audio player
      audacious # audio player
      audacious-plugins # audio player plugins
      rhythmbox # audio player
      stable.handbrake # forced stable on 1/20/2023 due to build failure on unstable with ffmpeg
      vlc # video player
      shortwave # internet radio
      renoise # super cool mod-tracker-like audio app
      # gnomeExtensions.screen-lock # was incompatible with gnome version as of 7/22/2022
      # custom_python3 # for a language I don't care about but which remains too popular
      qFlipper # for Flipper Zero
      lightspark # Flash (ActionScript 3) runner
      ruffle # Flash (soon ActionScript 3) runner
      trufflehog # scans github repos for possible secrets checked in by accident
      inkscape-with-extensions # Vector graphics editor with extensions
      drawing # drawing program
      libjxl # JPEG XL image format reference implementation
      # nasc # REMOVED from nixpkgs (unmaintained, deprecated webkitgtk_4_0)
      csvkit # Various tools for working with CSV files such as csvlook, csvcut, csvsort, csvgrep, csvjoin, csvstat, csvsql, etc.
      unstable.csvquote # Wraps each field in a CSV file in quotes and escapes existing quotes and commas in the fields
      stable.limo # Linux-native, Proton-prefix-aware mod manager (added 2026-07-02; from pinned nixpkgs release-26.05 via the `stable` scope)
      libnotify # provides notify-send — desktop notifications for the peon-ping Claude hook (added 2026-07-05; pw-play/wpctl already cover its audio)
    ];
  };

  programs = {
    # Native Steam (FHS-wrapped) — migrating OFF flatpak 2026-06-20. The FHS
    # env synthesizes the /usr/lib layout Steam expects, with full home/disk
    # access (the thing flatpak's sandbox kept getting in the way of). Auto-
    # enables 32-bit graphics libs.
    steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports for Steam Remote Play
      # dedicatedServer.openFirewall = true;
    };
    # gamescope micro-compositor: gives games a presentable Vulkan surface,
    # fixing the vkd3d "Surface is not supported for presentation" crash that
    # NVIDIA + XWayland produces since GNOME 50 forced this box onto Wayland.
    # Validated on the RTX 3080 Ti (vkcube renders). Launch games via Steam
    # opts: gamescope --backend sdl -W 3440 -H 1440 -f -- %command%
    gamescope = {
      enable = true;
      capSysNice = true;
    };
    ssh.startAgent = true;
    mosh = {
      enable = true;
      openFirewall = true;
    };
    gamemode.enable = true; # for steam
    dconf.enable = true;
    direnv.enable = true;
  };

  # Fonts!
  fonts = {
    fontDir.enable = true;
    enableGhostscriptFonts = true;
    packages = with pkgs; [
      corefonts
      inconsolata
      liberation_ttf
      powerline-fonts
      google-fonts
      noto-fonts
      noto-fonts-cjk-sans # renamed from noto-fonts-cjk (split sans/serif)
      noto-fonts-color-emoji # renamed from noto-fonts-emoji
      fira-code
      fira-code-symbols
      font-awesome
      hack-font
      # `nerdfonts` bundle was split into per-font `nerd-fonts.*` in 24.11; picking a sensible subset:
      nerd-fonts.symbols-only
      nerd-fonts.fira-code
      nerd-fonts.hack
      nerd-fonts.terminess-ttf # "Terminus Nerd Font" (was terminus-nerdfont) — matches kmscon config.font-name
      source-code-pro
      hasklig # source code pro plus more ligatures, https://github.com/i-tu/Hasklig
      gentium # https://software.sil.org/gentium/
      eb-garamond # my favorite serif font
      atkinson-hyperlegible # possibly my favorite sans serif font; https://brailleinstitute.org/freefont
      inter # great helvetica clone; https://rsms.me/inter/
      key-rebel-moon # my favorite monospaced proprietary font with obfuscated name
      tech-alive # another favorite sans serif font with obfuscated name
    ];
  };

  environment = {
    pathsToLink = [
      "/share/nix-direnv"
    ];
    # Gnome package exclusions
    gnome.excludePackages = (with pkgs; [
      gnome-photos
      gnome-tour
    ]) ++ (with pkgs; [
      cheese # webcam tool
      gnome-music
      gnome-terminal
      gedit # text editor
      epiphany # web browser
      # evince # document viewer
      gnome-characters
      totem # video player
      tali # poker game
      iagno # go game
      hitori # sudoku game
      atomix # puzzle game
    ]);

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    systemPackages = with pkgs; [
      # hunk (github.com/modem-dev/hunk) — terminal-first diff viewer. It's a
      # Bun/bun2nix FLAKE, not in nixpkgs. This machine is CHANNEL-based (no flake
      # inputs), so we pull it declaratively via a REV-PINNED builtins.getFlake
      # (the pin keeps `nixos-rebuild` eval pure/reproducible; flakes are enabled
      # system-wide in /etc/nix/nix.conf). TO UPDATE: bump the rev below to a newer
      # modem-dev/hunk commit, then `ixnay reify`. (When thelio finally migrates to
      # a flake-based config, replace this with a proper `inputs.hunk` + follows.)
      # NB: evaluating this external flake instantiates nixpkgs across all default
      # systems, so it (and ONLY it) emits the harmless "26.05 last to support
      # x86_64-darwin" eval warning. Confirmed 2026-06-24 by toggling it off.
      # Accepted — hunk stays. Don't go re-hunting that warning's source.
      (builtins.getFlake "github:modem-dev/hunk/0a3cc064931a9d576882baee6daac7cfab3d0bbe").packages.x86_64-linux.default

      # ── app-parity batch (from ~/tower-app-parity.txt, 2026-06-13) ──────────────
      # Present on BOTH the framework laptop AND the Mac but missing here after
      # thelio sat untouched ~2.5 years. Each name mechanically verified to resolve
      # in the current channel (nix eval) before adding; `mkdir` (not a pkg) and
      # `sd` (already listed above) excluded. The laptop-only (93) and mac-only (31)
      # tiers in that file are still pending deliberate selection.
      zed-editor                    # the editor Peter asked for
      ghostty                       # terminal emulator (laptop-only tier; added on request)
      coreutils-prefixed            # the g-prefixed GNU tools (gtimeout, gdate, …)
      gh
      nodejs                        # unversioned: rides nixpkgs' current default (24.18.0 today)
      corepack
      bun
      pnpm
      nim
      nixd
      gemini-cli
      aspell
      bashInteractive
      bat
      capstone
      circumflex
      colordiff
      dirb
      exiftool
      fclones
      ffmpeg
      fontconfig
      gawkInteractive
      ghostscript
      gnugrep
      gnused
      jjui
      less
      libarchive
      libheif
      libwebp
      lz4
      murex
      nmap
      nnn
      nufmt
      nushell
      nushellPlugins.gstat
      nushellPlugins.query
      pandoc
      par2cmdline-turbo
      presenterm
      procps
      python312Packages.pygments
      qpdf
      sampler
      sc-im
      sourceHighlight
      television
      tesseract
      trippy
      unzip
      vsce
      binaryen
      wabt
      wasm-bindgen-cli
      wasm-tools
      wasmedge
      wasmtime
      wazero
      wdiff
      wiper
      xz
      zoxide
      zstd
      # ────────────────────────────────────────────────────────────────────────────

      # QEMU/KVM VM tooling. Quickemu covers Windows/Linux guests and can also
      # drive macOS guests; virtio-win/win-spice provide Windows guest drivers.
      quickemu
      virtio-win
      win-spice

      # PaperWM — scrollable/carousel tiling for GNOME (the laptop's WM; line 106 of
      # tower-app-parity.txt). Runs on GNOME *Wayland*, so GNOME dropping X11 does NOT
      # force a switch to Niri, and the GNOME app/settings ecosystem stays. Package is
      # channel-matched to GNOME 50; enable it in GNOME Extensions after reify.
      gnomeExtensions.paperwm

      tmux # system-wide so the fleet's non-interactive SSH (and the dorktide agent session) find it on PATH — no abs-path hack
      # Lua toolchain — the SHARED dotfiles (also on framework-nixos + the
      # nix-darwin Mac) assume these. thelio (freshly resurrected) lacked them,
      # so `env: luajit: No such file or directory` aborted ~half of shell init
      # ("half my functions not loading"). luajit is the critical one.
      # NOTE: NOT plain `luajit` — it ships ZERO lua modules, so `require("lfs")`
      # (LuaFileSystem) throws and breaks rm-safe + other dotfiles luajit scripts,
      # even for env-scrubbed subprocess invocations. `luajit.withPackages` bakes the
      # modules into luajit's OWN package.path/cpath so require() resolves anywhere.
      # Mirrors ~/.config/nix/flake.nix `luajitWithPackages` (the synced Mac config).
      (pkgs.luajit.withPackages (ps: with ps; [
        alt-getopt basexx busted cjson lpeg lua_cliargs luabitop luacheck
        luafilesystem luasocket luasystem moonscript penlight sqlite tl
      ]))
      # LuaRocks now exports compat53 itself. Keeping it inside `withPackages`
      # would flatten two producers of compat53/module.lua into one buildEnv and
      # fail an otherwise ordinary Nixpkgs update. This wrapper preserves the
      # CLI without merging its library tree into LuaJIT's module environment.
      (writeShellApplication {
        name = "luarocks";
        text = "exec ${luajitPackages.luarocks}/bin/luarocks \"$@\"";
      })
      luajitPackages.moonscript # `moonc` CLI for moonrun/yuerun (separate from the baked module)
      sd # sed-alternative the dotfiles call
      # NOTE: yuescript (`yue`) is NOT in nixpkgs — needs a separate source later.
      # nordic # for nordic theme # REMOVED from nixpkgs (2026-08 lock bump): depended on gtk-engine-murrine (unmaintained, GTK 2). whitesur themes below still work.
      whitesur-gtk-theme
      whitesur-icon-theme
      # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
      vim # it's no emacs
      emacs # it's no vim
      bash # The venerable GNU Bourne Again shell
      # bash-completion # Programmable completion for the bash shell # note: caused problems
      # bash-preexec # Bash preexec and precmd functions # disabled since it's pulled in via a dotfile function now
      zsh # A user-friendly and interactive shell which is yet not sufficiently better than Bash to merit its use
      oils-for-unix # A Posix shell that aims to replace Bash (was `oil`). We'll see...
      shellcheck # A static analysis tool for shell scripts
      nix-bash-completions # bash completions for nix
      nixos-option # for searching options
      inotify-tools # for watching files programmatically
      nix-index # also provides nix-locate
      # nix-software-center # for installing nix packages via a GUI
      direnv # for loading environment variables from .env and .envrc files
      has # for verifying the availability and version of executables
      nix-direnv # direnv integration for nix
      gptfdisk # for gdisk
      file # file type identification
      git # the stupid content tracker
      git-lfs # git large file storage (for large AI models, usually)
      meld # visual diff and merge tool
      bind # provides nslookup etc
      inetutils # provides ping telnet etc
      xinetd # provides tftp etc. (originally installed to play with symbolics opengenera)
      # obtaining files:
      wget # wget is better than curl because it will resume with exponential backoff
      curl # curl is better than wget because it supports more protocols
      unstable.yt-dlp # for downloading videos from youtube and other sites (youtube-dl was marked insecure/EOL — last release 2021; yt-dlp is the maintained drop-in fork, matching this file's own "use yt-dlp instead" guidance below). 2026-07-05 flake migration
      ytmdl # for downloading music from youtube
      # clipgrab # REMOVED from nixpkgs (unmaintained since 2022, vulnerable qt5 webengine); use yt-dlp instead
      sshfs # for mounting remote filesystems
      cachix # for downloading pre-built binaries
      comma # for trying out software, see "let" section above
      hwinfo # hardware info
      uget # a download manager GUI
      obsidian # a note-taking app based on plain markdown files
      ## Timers
      gnome-solanum # timer GUI
      uair # a minimal pomodoro timer GUI/TUI
      timer # a `sleep` with progress TUI
      peaclock # a nice timer TUI
      et # A minimal (egg) timer TUI based on libnotify
      ## various process viewers
      htop # better than top
      btop # better than htop
      bottom # a modern alternative to top
      gotop # a terminal based graphical activity monitor inspired by gtop and vtop
      atop # advanced top
      iotop iotop-c # iotop-c is a fork of iotop with a curses interface
      nmon # for monitoring system performance
      wsysmon # like Windows Task Manager but for Linux
      monitor # yet another sexy system monitor
      nload # network load monitor
      nethogs # network bandwidth monitor
      ioping # disk latency tester
      sysz # An fzf-based terminal UI for systemctl
      ranger # file manager
      fzf # fuzzy finder
      unstable.visidata # https://github.com/saulpw/visidata
      zenith-nvidia # zoom-able charts (there is also a non-nvidia version)
      stable.nvtopPackages.nvidia # for GPU info # nvtop was restructured into nvtopPackages.* upstream; .nvidia matches this box's GPUs (was bare `stable.nvtop`, gone in 26.05)
      # sysstat # not sure if needed, provides sa1 and sa2 commands meant to be run via crond?
      dool # dstat's maintained fork (dstat removed from nixpkgs). e.g.: dool -cdnpmgs --top-bio --top-cpu --top-mem
      duc # disk usage visualization, highly configurable
      gdu # go disk usage, great way to visualize disk usage
      baobab # radial treemap of disk usage
      ncdu # "ncurses du (disk usage)"
      duf # really nice disk usage TUI
      gping # ping with a graph
      bmon # network bandwidth monitor
      kmon # kernel module monitor
      lsof # for listing open files and ports
      # for showing off nixos:
      fastfetch # system info (neofetch was removed from nixpkgs; fastfetch is the maintained replacement)
      nix-tree # show nixpkgs tree
      hydra-check # show hydra status
      ripgrep # rg, the best grep
      fd # a better "find"
      rdfind # finds dupes, optionally acts on them
      socat # netcat on steroids
      mcfly # fantastic replacement for control-R history search
      atuin # a better history search, with sync and fuzzy search
      # exa # a better ls # deprecated and replaced 9/2023 with eza due to being unmaintained
      eza # a better ls
      tree # view directory structure
      tokei # fast LOC counter
      p7zip # 7zip
      xxhash # very fast hash (renamed from xxHash)
      dcfldd # dd with progress bar and inline hash verification
      unrar # a rar extractor
      xclip # clipboard interaction
      ascii # commandline ascii chart
      cowsay # a classic
      bc # calculator (also a basic language... possibly useful for education?)
      conky # system monitor
      # latest.firefox-nightly-bin # firefox # had to disable for now due to segfault on unstable: https://github.com/NixOS/patchelf/issues/520
      firefox-beta
      chromium # like chrome but without the google
      wezterm # nerdy but very nice terminal
      kitty # another nice terminal emulator
      alacritty # a super fast terminal
      cool-retro-term # a retro terminal emulator
      gnome-tweaks # may give warning about being outdated? only shows it once, though?
      glib # seems to be an undeclared dependency of some gnome tweaks such as Night Theme Switcher
      gnomeExtensions.appindicator # for system tray icons
      # gnomeExtensions.clipboard-indicator # "incompatible with current Gnome version"
      gnomeExtensions.dash-to-dock # for moving the dock to the bottom
      # gnomeExtensions.dash-to-dock-toggle # "incompatible with current Gnome version"
      # gnomeExtensions.dash-to-dock-animator # "incompatible with current Gnome version"
      # gnomeExtensions.miniview # REMOVED (incompatible with GNOME 50, dropped from nixpkgs)
      gnomeExtensions.freon # for monitoring CPU and GPU temps
      # gnomeExtensions.gamemode # "incompatible with current Gnome version"
      # gnomeExtensions.hide-top-bar # may be leading to instability with alt-tabbing freezing the GUI from fullscreen apps (games)
      gnomeExtensions.vitals # for monitoring CPU and GPU temps
      # gnomeExtensions.cpufreq # incompatible with gnome version as of 11/21/2022
      # gnomeExtensions.weather # doesn't work with latest gnome
      # gnomeExtensions.sermon
      # gnomeExtensions.scrovol # doesn't work with latest gnome
      gnomeExtensions.pop-shell # for tiling windows
      gnomeExtensions.rclone-manager # adds an indicator to the top panel so you can manage the rclone profiles configured in your system
      gnomeExtensions.lock-keys # for showing caps lock etc
      # gnomeExtensions.random-wallpaper # "incompatible with current Gnome version"
      # gnomeExtensions.user-themes # "incompatible with current Gnome version"
      imwheel # for mouse wheel scrolling
      bucklespring # for keyboard sounds
      # gnomeExtensions.toggle-imwheel # for mouse wheel scrolling # "incompatible with current Gnome version"
      # gnomeExtensions.what-watch # analog floating clock # "incompatible with current Gnome version"
      sushi # file previewer (just hit spacebar in Gnome Files)
      libreoffice-fresh # needed for gnome sushi to preview Office files, otherwise *big hang*. No idea if I picked the right LibreOffice as there's like a dozen variants and NO docs about this.
      dconf-editor # for editing gnome settings
      zenity # for zenity, a GUI dialog box tool
      nitrogen # wallpaper/desktop image manager
      dconf2nix # for converting dconf settings to nix
      home-manager # for managing user settings in Nix
      xbacklight # for controlling screen brightness (renamed from xorg.xbacklight)
      cargo # rust package manager
      rustc # rust compiler
      gcc # C compiler
      gnumake # make
      cosmocc-bin # Cosmopolitan (Actually Portable Executable) C/C++ toolchain; use via CC=cosmocc, CXX=cosmoc++ — prebuilt from cosmo.zip, NOT nixpkgs (see ../cosmocc-bin.nix)
      idris2 # Idris2 functional statically-typed programming language that looks cool and compiles to C
      chez # Chez Scheme (useful for idris)
      gmp # GNU Multiple Precision Arithmetic Library
      # gnupg # installed separately in config elsewhere
      pinentry-gnome3 # gpg/gnupg password entry GUI (pkgs.pinentry meta removed; pick a flavor)
               # https://github.com/NixOS/nixpkgs/commit/3d832dee59ed0338db4afb83b4c481a062163771
      pkg-config # for compiling stuff
      # $%&* locales...
      glibcLocales # for locales
      # lsb-release # sys info # nah, do "source /etc/os-release; echo $PRETTY_NAME" instead
      # clang # removed due to collisions; install on project basis
      evince # gnome's document viewer (pdfs etc)
      zathura # a better document viewer (pdf's etc)
      groff # seems to be an undeclared dependency of evince...
      pciutils # for lspci
      perf-tools # for profiling
      vulkan-tools # for profiling
      pv # pipe viewer
      smartmontools
      gsmartcontrol
      efibootmgr # for managing EFI boot entries
      wmctrl # for controlling window managers
      # netdata # enabled via services.netdata.enable
      psmisc # provides killall, fuser, prtstat, pslog, pstree, peekfd
      hdparm # for hard drive info
      cacert # for curl certificate verification
      mkpasswd # for generating passwords
      zfs # the best filesystem on the planet
      polybar # status bar
      imagemagick # for converting images
      appimage-run # to run appimages
      rescuetime # usage tracking; currently configured to run for all users, above
      alsa-utils # for alsa sound utilities
      mpv # media player
      openrazer-daemon # for razer stuff
      ## start WINE stuff
      # support both 32- and 64-bit applications
      # wineWow64Packages.unstableFull
      # support 32-bit only
      # wine
      # support 64-bit only
      # (wine.override { wineBuild = "wine64"; })
      # wine-staging (version with experimental features)
      # wineWow64Packages.staging
      # winetricks (all versions)
      # winetricks
      # native wayland support (unstable)
      # wineWow64Packages.waylandFull
      (wineWow64Packages.unstableFull.override {
        wineRelease = "staging";
        mingwSupport = true;
      })
      unstable.winetricks # winetricks is a helper script to download and install various redistributable runtime libraries needed to run some programs in Wine.
      unstable.protontricks # automates installing winetricks packages for proton
      ## end WINE stuff

      # stuff for my specific hardware
      system76-firmware # for system76 firmware updates
    ];

    variables = {
      EDITOR = "code";
      BROWSER = "firefox";
      # fix for this curl issue with https requests: https://github.com/NixOS/nixpkgs/issues/148686
      CURL_CA_BUNDLE = "/etc/pki/tls/certs/ca-bundle.crt"; # this is the value of $SSL_CERT_FILE ; obviously this is brittle and may change
      # ^ May be fixed by adding `cacert` to systemPackages; haven't checked yet though
      # McFly config: https://github.com/cantino/mcfly
      MCFLY_INTERFACE_VIEW = "BOTTOM";
      MCFLY_RESULTS = "50";
      MCFLY_FUZZY = "2";
      NIXPKGS_ALLOW_UNFREE = "1";
      # friggin' keeps picking the wrong video card!!
      DXVK_FILTER_DEVICE_NAME = "GeForce RTX 3080 Ti";
      DIRENV_WARN_TIMEOUT = "60s";
      # tell gnome which window manager to prefer
      # WINDOW_MANAGER = "wmaker"; # windowmaker
    };

    sessionVariables = rec {
      XDG_CACHE_HOME  = "\${HOME}/.cache";
      XDG_CONFIG_HOME = "\${HOME}/.config";
      XDG_BIN_HOME    = "\${HOME}/.local/bin";
      XDG_DATA_HOME   = "\${HOME}/.local/share";
      # Steam needs this to find Proton-GE
      # STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
      PATH = [
        "\${XDG_BIN_HOME}"
      ];
      # GNUSTEP_USER_ROOT = "\${XDG_CONFIG_HOME}/GNUstep";
    };

    # adds /usr/share/dict/words via 'scowl', which is depended on by some things;
    # see: https://github.com/NixOS/nixpkgs/issues/16545
    wordlist.enable = true;
    # the following may not need manual configuration if media-session is enabled
    # etc = {
    #   "wireplumber/bluetooth.lua.d/51-bluez-config.lua".text = ''
    #     bluez_monitor.properties = {
    #       ["bluez5.enable-sbc-xq"] = true,
    #       ["bluez5.enable-msbc"] = true,
    #       ["bluez5.enable-hw-volume"] = true,
    #       ["bluez5.headset-roles"] = "[ hsp_hs hsp_ag hfp_hf hfp_ag ]"
    #     }
    #   '';
    # };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    # enableSSHSupport = true;
  };

  # nix-ld: lets unpatched, generic-Linux dynamically-linked binaries run on
  # NixOS — e.g. the official Claude Code install at ~/.local/bin/claude, whose
  # ELF interpreter is /lib64/ld-linux-x86-64.so.2. Enabling this installs the
  # real nix-ld loader there (replacing stub-ld) and auto-exports NIX_LD and
  # NIX_LD_LIBRARY_PATH via sessionVariables (so you do NOT hand-set those).
  # Add libraries here as `ldd <binary>` / runtime errors reveal missing .so's.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib # libstdc++ / libgcc_s (what most node/bun binaries need)
      zlib
    ];
  };

  security = {
    # Don't ask for my password quite as often
    sudo.extraConfig = "Defaults timestamp_timeout=60";
    # expand open files limit
    # pam.loginLimits = [
    #   {
    #     domain = "*";
    #     type = "-";
    #     item = "nofile";
    #     value = "9001";
    #   }
    # ];
  };

  # Quickemu/QEMU guest conveniences. This installs the SPICE USB helper so
  # unprivileged sessions can redirect selected USB devices into VMs.
  virtualisation.spiceUSBRedirection.enable = true;

  # Docker and other VM options
  virtualisation.docker = {
    # enable = true;
    enableOnBoot = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
      daemon.settings = { }; # https://docs.docker.com/engine/reference/commandline/dockerd/#daemon-configuration-file
    };
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
    enableNvidia = true; # enabling may let you use ML stuff that can then use the GPU via CUDA etc.
    # storageDriver = null; # by default, lets docker pick
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  ##### System level configs

  system = {
    # copySystemConfiguration copied /etc/nixos/configuration.nix into the system closure.
    # It is UNSUPPORTED under flakes (a flake is a whole tree, not one file) and now hard-errors,
    # so it is disabled by the flake migration (2026-07-05). The config is source-controlled here
    # (Git repository at /etc/nixos) which supersedes the "in case you delete it" rationale anyway.
    copySystemConfiguration = false;

    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    stateVersion = "22.05"; # Did you read the comment?

    # autoupgrade? (disabled — `ixnay reify` is the sole rebuild path)
    autoUpgrade.enable = false;
    autoUpgrade.allowReboot = false; # reboot if kernel changes?
    # Flake-based target (replaces the meaningless-under-flakes `autoUpgrade.channel`).
    # Only consulted if autoUpgrade.enable is ever flipped to true.
    autoUpgrade.flake = "/etc/nixos#thelio-nixos";
  };

  ### Nix settings
  nix = {
    settings = {
      keep-outputs = true;
      keep-derivations = true;
      # we have 64 cores and 128 threads on this beast, so...
      # A value of "auto" may be permitted for 'max-jobs' (to use all available cores) but is not pure...
      # 'max-jobs' apparently also sets the number of possible concurrent downloads
      # 'cores' is like the "make -j" option; note that some packages don't like concurrent builds,
      # but that's their responsibility to limit themselves, in that case.
      # The Nix store and build directory now live on mirrored NVMe. Balance
      # independent derivations against per-derivation build threads so the
      # nominal scheduler budget matches this host's 128 hardware threads.
      # Sixteen jobs also leave roughly 8 GiB of RAM per job at full occupancy.
      max-jobs = 16;
      cores = 8;
      # Build trees are as metadata-heavy as the store. Keep them on the
      # mirrored NVMe nixpool rather than creating churn on the HDD root.
      build-dir = "/nix/var/nix/builds";
      # use hardlinks to save space?
      auto-optimise-store = true;
      # flakes
      experimental-features = [ "nix-command" "flakes" ];
      warn-dirty = false;
      substituters = lib.mkBefore [ "https://ai.cachix.org" ];
      trusted-users = [ "@root" "@wheel" ];
    };
    # automatically run gc?
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

}
