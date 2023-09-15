# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

# { config, pkgs, nixpkgs, stable, unstable, trunk, lib, home-manager, nixos-hardware, ... }:
{ config, pkgs, lib, ... }:
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
  unstable = import <nixos-unstable> {
    config = { allowUnfree = true; };
    # overlays = [
    # # use native cpu optimizations
    # # note: NOT PURE
    #   (self: super: {
    #     stdenv = super.impureUseNativeOptimizations super.stdenv;
    #   })
    # ];
  };
  stable = import <nixos-stable> {
    config = { allowUnfree = true; };
  };
  master = import <nixos-master> {
    config = { allowUnfree = true; };
  };
  # my custom proprietary fonts
  key-rebel-moon = pkgs.callPackage ./key-rebel-moon.nix { };
  tech-alive = pkgs.callPackage ./tech-alive.nix { };
  # which particular version of elixir and erlang I want globally
  erlang = unstable.erlang; # I like to live dangerously. For fallback, use stable of: # erlangR25;
  elixir = pkgs.beam.packages.erlangR26.elixir_1_15;
  # libretro = stable.libretro;
  comma = (import (pkgs.fetchFromGitHub {
    owner = "nix-community";
    repo = "comma";
    rev = "v1.6.0";
    sha256 = "sha256-5HNH/Lqj8OU/piH3tvPRkINXHHkt6bRp0QYYR4xOybE=";
  })).default;
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
    (self: super: { nix-direnv = super.nix-direnv.override { enableFlakes = true; }; } )
  ];

  # Any temporarily-allowed insecure packages.
  nixpkgs.config.permittedInsecurePackages = [
    "xrdp-0.9.9" # added 1/5/2023
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
    # Boot using the latest kernel: pkgs.linuxPackages_latest
    # Boot with bcachefs test: pkgs.linuxPackages_testing_bcachefs
    # TODO: investigate zen kernel
    # Commented out to use stable for now :/
    # kernelPackages = pkgs.linuxPackages_latest; #pkgs.linuxPackages_rpi4;
    # kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages; # for latest zfs-compatible kernel

    hardwareScan = true; # tried to make udev run faster at boot by falsing, but then my keyboard and mouse stopped working lol (usb driver not loaded, perhaps?)

    kernel.sysctl = {
      "vm.swappiness" = 40; # 90 when swapping to ssd; default is 60
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
                     "zfs.zfs_arc_max=17179869184" # 16GB
                     "zfs.prefetch_disable=1"
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
      kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];
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
      zfs_arc_max=17179869184 \
      prefetch_disable=1
    '';
  };

  # Networking details
  networking = {
    hostName = "nixos"; # Define your hostname.
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
    user = {
      services = {
        # my custom grandfather clock gong script
        clocksound = let
          scriptUrl = "https://gist.githubusercontent.com/pmarreck/2a2de1a5227383625829fdaf9b50c4a3/raw/d0a987055b83bf2fa5a0500ce2c948fd175fa4f1/grandfather_clock_chime.bash";
          scriptContent = builtins.readFile (builtins.fetchurl scriptUrl);
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
            OnCalendar = "hourly";
            # OnCalendar = [
            #   "*-*-* 08..23:00:00"  # Every hour from 08:00 to 23:00
            #   "*-*-* 00:00:00"      # At 00:00
            # ];
            Unit = "clocksound.service";
            # Persistent = true;
          };
        };
      };
    };
    services = {
      # some of these things were tweaked to speed up booting.
      # See output of: systemd-analyze blame
      systemd-journal-flush.enable = false; # had super high disk ute in jbd2
      # note that the following may cause zfs pools not to mount, even though it shouldn't;
      # please see discussion @ https://github.com/openzfs/zfs/issues/10891
      # systemd-udev-settle.enable = false; # speed up booting
      NetworkManager-wait-online.enable = false; # speed up booting
      # more booting speedup... for the next 2 lines, see: https://github.com/NixOS/nixpkgs/issues/41055
      modem-manager.enable = false;
      "dbus-org.freedesktop.ModemManager1".enable = false;
      nix-daemon.serviceConfig = {
        CPUWeight = 50;
        IOWeight = 50;
      };
      # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
      "getty@tty1".enable = false;
      "autovt@tty1".enable = false;
    };
    # https://discourse.nixos.org/t/desktop-oriented-kernel-scheduler/12588/3
    extraConfig = ''
      DefaultCPUAccounting=yes
      DefaultMemoryAccounting=yes
      DefaultIOAccounting=yes
    '';
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
      hwRender = true;
      autologinUser = "pmarreck";
      fonts = [
                { name = "Terminus NerdFont"; package = pkgs.terminus-nerdfont; }
                { name = "Powerline Fonts"; package = pkgs.powerline-fonts; }
                { name = "Source Code Pro"; package = pkgs.source-code-pro; }
                { name = "Fira Code"; package = pkgs.fira-code; }
               ];
      extraOptions = "--term xterm-256color --font-size 16";
    };

    # Enable the X11 windowing system.
    xserver = {
      enable = true;
      # Enable the GNOME Desktop Environment.
      displayManager.gdm.enable = true;
      desktopManager.gnome.enable = true;
      # Reinstate the minimize/maximize buttons!
      # To list all possible settings, try this:
      # > gsettings list-schemas
      # then pick one and use it here:
      # > gsettings list-recursively <schema-name>
      # Try to keep the settings groups in alphabetical order.
      desktopManager.gnome.extraGSettingsOverrides = ''
        [org.gnome.desktop.interface]
        gtk-theme='Nordic'
        text-scaling-factor=1.25

        [org.gnome.desktop.wm.preferences]
        button-layout=':minimize,maximize,close'
        resize-with-right-button=true
        theme='Nordic'

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
      # wayland wonky with nvidia, still
      displayManager.gdm.wayland = false;
      # use nvidia card for xserver
      videoDrivers = ["nvidia"];
      # Configure keymap in X11
      xkbOptions = "mod_led:compose,compose:ralt,terminate:ctrl_alt_bksp,shift:breaks_caps";
      layout = "us";
      xkbVariant = "";
      # Enable automatic login for the user.
      displayManager.autoLogin.enable = false;
      # if above is true, you'd still need to unlock the keyring anyway and sometimes that modal dialog gets stuck, forcing a reboot
      displayManager.autoLogin.user = "pmarreck";
      # Enable touchpad support (enabled default in most desktopManager).
      # libinput.enable = true;
      # try out windowmaker!
      # windowManager.windowmaker.enable = true;
      # displayManager.defaultSession = "none+windowmaker";
    };

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
    # Journald was taking too long to copy from runtime memory to disk at boot
    # set storage to "auto" if you're trying to troubleshoot a boot issue
    journald.extraConfig = ''
      Storage=auto
      SystemMaxFileSize=300M
      SystemMaxFiles=50
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
    udev.packages = with pkgs; [ gnome.gnome-settings-daemon ];

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
      enableWinbindd = true;
      extraConfig = ''
        [global]
        workgroup = WORKGROUP
        server string = Samba Server %v
        netbios name = nixos
        security = user
        map to guest = bad user
        dns proxy = no
        bind interfaces only = yes
        interfaces = lo enp68s0 wlo2 wlp69s0
        log file = /var/log/samba/log.%m
        max log size = 1000
        syslog = 0
        panic action = /usr/share/samba/panic-action %d
        server role = standalone server
        passdb backend = tdbsam
        obey pam restrictions = yes
        unix password sync = yes
        passwd program = /usr/bin/passwd %u
        passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
        pam password change = yes
        map to guest = bad user
        usershare allow guests = yes
        [homes]
        comment = Home Directories
        browseable = no
        read only = no
        create mask = 0700
        directory mask = 0700
        valid users = %S
        [printers]
        comment = All Printers
        browseable = no
        path = /var/spool/samba
        printable = yes
        guest ok = no
        read only = yes
        create mask = 0700
        [print$]
        comment = Printer Drivers
        path = /var/lib/samba/printers
        browseable = yes
        read only = yes
        guest ok = no
      '';
    };

    # Fartpak
    flatpak.enable = true;

    # ZFS, yeah, baby, yeah!!
    zfs = {
      autoScrub.enable = true;
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
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.beta; #vulkan_beta;
  # hardware.nvidia.powerManagement.enable = true; # should only be used on laptops, maybe?

  # Enable sound with pipewire.
  # sound.enable = true;
  hardware.pulseaudio.enable = false;
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
    extraGroups = [ "networkmanager" "wheel" "tty" "input" "openrazer" "audio" "plugdev" ];
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
      openssl # security
      curlpp # for curl bindings in C++
      pkg-config # for compiling C/C++
      gcc # compiler for C
      opencl-clhpp # for opencl
      ocl-icd # for opencl
      patchelf # for fixing up binaries in nix
      stable.cudaPackages.cudatoolkit # for tensorflow
      mono # for C#/.NET stuff
      unstable.vscode # nice gui editor
      unstable.gnome-builder # code editor
      unstable.o # Simple text editor/IDE intentionally limited to VT100; https://github.com/xyproto/o
      unstable.micro # sort of an enhanced nano
      master.gum # looks like a super cool TUI tool for shell scripts: https://github.com/charmbracelet/gum
      # postgresql # the premier open-source database # we are only using project-based pg's for now
      # asdf-vm # version manager for many languages
      python311Packages.pygments # syntax highlighting for 565 languages in terminal
      conda # python package manager (ew. but need it for LLM's)
      asciinema # record terminal sessions
      glow # markdown viewer
      delta #syntax highlighter for git
      stable.ripgrep-all # ripgrep-all is a wrapper around ripgrep, fd, and git that allows you to search through your codebase using ripgrep syntax.
      fsearch # file search GUI
      parallel # parallelize shell commands
      stable.spotifyd # spotify streamer daemon
      stable.spotify # forced stable on 2/16/2023 due to build failure on unstable
      spotify-tui # spotify terminal UI
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
      free42 # hp-42S reverse-engineered from the ground up
      # numworks-epsilon # whoa, cool calc! # disabled due to disuse, and troubleshooting an issue
      browsh # graphical web browser in the terminal
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
      proton-caller # automates launching proton games
      # bottles
      # gnutls # possibly needed for bottles to work correctly with battle.net launcher?
      discord # chat app for gamers
      # razergenie # razer mouse/keyboard config tool. disabled because seems lamer than polychromatic
      polychromatic # razer mouse/keyboard config tool
      master.whatsapp-for-linux # whatsapp desktop client
      master.signal-desktop # signal desktop client
      telegram-desktop # chat app
      transmission-gtk # torrent client
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
      mailspring # nice open-source email client
      # thunderbird # the venerable email client
      # evolutionWithPlugins # email client
      recoll # full-text search tool
      moar # a better "less"
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
        stable.tome2 # roguelike
        nethack # roguelike
        unnethack # roguelike
        harmonist # roguelike
        hyperrogue # roguelike
        crawl # roguelike
        crawlTiles # roguelike
        brogue # roguelike
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
      gamehub # game launcher
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
      nasc # "do maths like a normal person", it says. I'm intrigued.
      csvkit # Various tools for working with CSV files such as csvlook, csvcut, csvsort, csvgrep, csvjoin, csvstat, csvsql, etc.
      unstable.csvquote # Wraps each field in a CSV file in quotes and escapes existing quotes and commas in the fields
    ];
  };

  programs = {
    # Enable Steam # Note: using via flatpak for now due to incompatibilities
    # steam = {
    #   # enable = true;
    #   remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    #   # dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    # };
    ssh.startAgent = true;
    gamemode.enable = true; # for steam
    dconf.enable = true;
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
      noto-fonts-cjk
      noto-fonts-emoji
      fira-code
      fira-code-symbols
      font-awesome
      hack-font
      nerdfonts
      terminus-nerdfont
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
    ]) ++ (with pkgs.gnome; [
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
      nordic # for nordic theme
      whitesur-gtk-theme
      whitesur-icon-theme
      # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
      vim # it's no emacs
      emacs # it's no vim
      bash # The venerable GNU Bourne Again shell
      # bash-completion # Programmable completion for the bash shell # note: caused problems
      # bash-preexec # Bash preexec and precmd functions # disabled since it's pulled in via a dotfile function now
      zsh # A user-friendly and interactive shell which is yet not sufficiently better than Bash to merit its use
      oil # A Posix shell that aims to replace Bash. We'll see...
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
      master.youtube-dl # for downloading videos from youtube and other sites
      ytmdl # for downloading music from youtube
      clipgrab # for downloading videos from youtube and other sites
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
      master.visidata # https://github.com/saulpw/visidata
      zenith-nvidia # zoom-able charts (there is also a non-nvidia version)
      stable.nvtop # for GPU info # downgraded to stable on 6/23/2023 due to build failure on unstable
      # sysstat # not sure if needed, provides sa1 and sa2 commands meant to be run via crond?
      dstat # example use: dstat -cdnpmgs --top-bio --top-cpu --top-mem
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
      neofetch # system info
      nix-tree # show nixpkgs tree
      hydra-check # show hydra status
      ripgrep # rg, the best grep
      fd # a better "find"
      rdfind # finds dupes, optionally acts on them
      mcfly # fantastic replacement for control-R history search
      atuin # a better history search, with sync and fuzzy search
      # exa # a better ls # deprecated and replaced 9/2023 with eza due to being unmaintained
      eza # a better ls
      tree # view directory structure
      tokei # fast LOC counter
      p7zip # 7zip
      xxHash # very fast hash
      dcfldd # dd with progress bar and inline hash verification
      unrar # a rar extractor
      xclip # clipboard interaction
      ascii # commandline ascii chart
      cowsay # a classic
      bc # calculator (also a basic language... possibly useful for education?)
      conky # system monitor
      latest.firefox-nightly-bin # firefox
      chromium # like chrome but without the google
      wezterm # nerdy but very nice terminal
      kitty # another nice terminal emulator
      alacritty # a super fast terminal
      cool-retro-term # a retro terminal emulator
      gnome.gnome-tweaks # may give warning about being outdated? only shows it once, though?
      glib # seems to be an undeclared dependency of some gnome tweaks such as Night Theme Switcher
      gnomeExtensions.appindicator # for system tray icons
      # gnomeExtensions.clipboard-indicator # "incompatible with current Gnome version"
      gnomeExtensions.dash-to-dock # for moving the dock to the bottom
      # gnomeExtensions.dash-to-dock-toggle # "incompatible with current Gnome version"
      # gnomeExtensions.dash-to-dock-animator # "incompatible with current Gnome version"
      gnomeExtensions.miniview # for quick window previews
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
      gnome.sushi # file previewer (just hit spacebar in Gnome Files)
      libreoffice-fresh # needed for gnome sushi to preview Office files, otherwise *big hang*. No idea if I picked the right LibreOffice as there's like a dozen variants and NO docs about this.
      gnome.dconf-editor # for editing gnome settings
      gnome.zenity # for zenity, a GUI dialog box tool
      nitrogen # wallpaper/desktop image manager
      dconf2nix # for converting dconf settings to nix
      home-manager # for managing user settings in Nix
      xorg.xbacklight # for controlling screen brightness
      cargo # rust package manager
      rustc # rust compiler
      gcc # C compiler
      gnumake # make
      cosmocc # Cosmopolitan (Actually Portable Executable) C/C++ toolchain; use via CC=cosmocc, CXX=cosmoc++
      idris2 # Idris2 functional statically-typed programming language that looks cool and compiles to C
      chez # Chez Scheme (useful for idris)
      gmp # GNU Multiple Precision Arithmetic Library
      # gnupg # installed separately in config elsewhere
      pinentry # for gpg/gnupg password entry GUI. why does it not install this itself? ah, found out...
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
      # wineWowPackages.unstableFull
      # support 32-bit only
      # wine
      # support 64-bit only
      # (wine.override { wineBuild = "wine64"; })
      # wine-staging (version with experimental features)
      # wineWowPackages.staging
      # winetricks (all versions)
      # winetricks
      # native wayland support (unstable)
      # wineWowPackages.waylandFull
      (wineWowPackages.unstableFull.override {
        wineRelease = "staging";
        mingwSupport = true;
      })
      winetricks # winetricks is a helper script to download and install various redistributable runtime libraries needed to run some programs in Wine.
      protontricks # automates installing winetricks packages for proton
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
    # Copy the NixOS configuration file and link it from the resulting system
    # (/run/current-system/configuration.nix). This is useful in case you
    # accidentally delete configuration.nix (which you should have source-controlled, anyway!).
    # Note: Also source-control hardware-configuration.nix, FYI!
    copySystemConfiguration = true;

    # This value determines the NixOS release from which the default
    # settings for stateful data, like file locations and database versions
    # on your system were taken. It‘s perfectly fine and recommended to leave
    # this value at the release version of the first install of this system.
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
    stateVersion = "22.05"; # Did you read the comment?

    # autoupgrade?
    autoUpgrade.enable = false;
    autoUpgrade.allowReboot = false; # reboot if kernel changes?
    autoUpgrade.channel = https://nixos.org/channels/nixos-22.05;
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
      # Current values may change and are being played with to find optimal combo
      max-jobs = 20;
      cores = 32;
      # use hardlinks to save space?
      auto-optimise-store = true;
      # flakes
      experimental-features = [ "nix-command" "flakes" ];
      warn-dirty = false;
    };
    # automatically run gc?
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

}
