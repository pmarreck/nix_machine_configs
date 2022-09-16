# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:
# add unstable channel definition for select packages, with unfree permitted
# Note that prior to this working you need to run:
# sudo nix-channel --add https://nixos.org/channels/nixos-unstable nixos-unstable
# to add to global channels and for user channels run
# nix-channel --add https://nixos.org/channels/nixos-unstable nixos-unstable
# for hardware-specific packages
# sudo nix-channel --add https://github.com/NixOS/nixos-hardware/archive/master.tar.gz nixos-hardware
# sudo nix-channel --update

let
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
  # my custom proprietary fonts
  key-rebel-moon = pkgs.callPackage ./key-rebel-moon.nix { };
  tech-alive = pkgs.callPackage ./tech-alive.nix { };
  # which particular version of elixir and erlang I want globally
  elixir = pkgs.beam.packages.erlangR25.elixir_1_13; # Elixir 1.14 was released Sept 1 2022 and is not yet in nixpkgs
in
{
  imports =
    [ # See the following on how to convert this to flakes or add the channel:
      # https://github.com/NixOS/nixos-hardware
      <nixos-hardware/system76>
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./zfs.nix
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

  # Early console config.
  console = {
    font = "ter-132n";
    packages = [pkgs.terminus_font];
    # keyMap = "us"; # inherited from x11 layout, below, I believe
    useXkbConfig = true;
    earlySetup = false;
  };

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Bootloader.
  boot = {
    cleanTmpDir = true;
    crashDump.enable = true;
    loader = {
      ## I switched from systemd-boot to grub2 when I figured out how to get onto zfs root,
      ## and the defaults seemed to work fine, don't know enough about boot/EFI yet to mess with it
      # systemd-boot.enable = false;
      grub = {
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
      };
      # efi.canTouchEfiVariables = true; # zfs config specifies false, so...
      # efi.efiSysMountPoint = "/boot/efi";
    };
    # Boot using the latest kernel: pkgs.linuxPackages_latest
    # Boot with bcachefs test: pkgs.linuxPackages_testing_bcachefs
    # TODO: investigate zen kernel
    # Commented out to use stable for now :/
    # kernelPackages = pkgs.linuxPackages_latest; #pkgs.linuxPackages_rpi4;
    # kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages; # for latest zfs-compatible kernel

    hardwareScan = true; # tried to make udev run faster at boot by falsing, but then my keyboard and mouse stopped working lol (usb driver not loaded, perhaps?)

    kernel.sysctl = {
      "vm.swappiness" = 20; # 90 when swapping to ssd; default is 60
      "vm.vfs_cache_pressure" = 50; # default is 100
      "vm.dirty_ratio" = 55; # https://sites.google.com/site/sumeetsingh993/home/experiments/dirty-ratio-and-dirty-background-ratio
      "vm.dirty_background_ratio" = 20;
      "kernel.task_delayacct" = 1; # so iotop/iotop-c can work; may add latency
      "kernel.sched_latency_ns" = 4000000;
      "kernel.sched_min_granularity_ns" = 500000;
      "kernel.sched_wakeup_granularity_ns" = 50000;
      "kernel.sched_migration_cost_ns" = 250000;
      "kernel.sched_cfs_bandwidth_slice_us" = 3000;
      "kernel.sched_nr_migrate" = 128;
    };

    kernelParams = [ "quiet"
                     "splash"
                     "boot.shell_on_fail"
                     "cgroup_no_v1=all"
                     "loglevel=2"
                     "rd.udev.log_level=2"
                     "udev.log_priority=2"
                     "nvidia_drm.modeset=1"
                     "systemd.unified_cgroup_hierarchy=yes"
                     "systemd.gpt_auto=0"
                     "zfs.zfs_arc_max=17179869184" # 16GB
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
      options zfs l2arc_noprefetch=0 \
      l2arc_write_boost=16777216 \
      l2arc_write_max=16777216 \
      l2arc_headroom=0 \
      l2arc_mfuonly=1 \
      zfs_arc_max=17179869184
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
  };

  systemd = {
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
      desktopManager.gnome.extraGSettingsOverrides = ''
        [org.gnome.desktop.wm.preferences]
        button-layout=':minimize,maximize,close'

        [org.gnome.settings-daemon.plugins.color]
        night-light-enabled=true
        night-light-temperature=2500
        night-light-schedule-automatic=true

        [org.gnome.SessionManager]
        auto-save-session=true

        [org.gnome.nautilus.preferences]
        always-use-location-entry=true
      '';
      # wayland wonky with nvidia, still
      displayManager.gdm.wayland = false;
      # use nvidia card for xserver
      videoDrivers = ["nvidia"];
      # Configure keymap in X11
      # xkbOptions = {
      #   "eurosign:e";
      #   "caps:escape" # map caps to escape.
      # };
      layout = "us";
      xkbVariant = "";
      # Enable automatic login for the user.
      displayManager.autoLogin.enable = false;
      # if above is true, you'd still need to unlock the keyring anyway and sometimes that modal dialog gets stuck, forcing a reboot
      displayManager.autoLogin.user = "pmarreck";
      # Enable touchpad support (enabled default in most desktopManager).
      # libinput.enable = true;
    };

    # Enable CUPS to print documents.
    printing.enable = true;

    # Enable sound with pipewire.
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      # If you want to use JACK applications, uncomment this
      #jack.enable = true;

      # use the example session manager (no others are packaged yet so this is enabled by default,
      # no need to redefine it in your config for now)
      #media-session.enable = true;
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
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable; #.vulkan_beta; #stable;
  # hardware.nvidia.powerManagement.enable = true; # should only be used on laptops, maybe?

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;

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
    extraGroups = [ "networkmanager" "wheel" "tty" "input" ];
    shell = pkgs.bash;
    hashedPassword = "$6$xLM1UDNfT/H8lbHK$jKAmqDp39Sj7O.ccOAN4tTBVOL4WoD6RaDcWa/Yg1XFE037sAGsN6WL4psvoKnanybrHYDwSFMWzHcCegp2ht0";

    # TODO: move these to home-manager
    packages = with pkgs; [
      erlangR25
      elixir
      unstable.vscode
      postgresql
      asdf-vm
      direnv
      nix-direnv
      delta #syntax highlighter for git
      ripgrep-all
      spotify
      spotify-tui
      slack
      figlet
      jq
      fortune
      speedread
      speedtest-cli
      markets
      qalculate-gtk
      free42 # hp-42S reverse-engineered from the ground up
      numworks-epsilon # whoa, cool calc!
      # unstable.mathematica # because why the heck not?
      # actually, NOPE:
      # This nix expression requires that Mathematica_13.0.1_BNDL_LINUX.sh is
      # already part of the store. Find the file on your Mathematica CD
      # and add it to the nix store with nix-store --add-fixed sha256 <FILE>.
      # Awaiting update to 13.1.0:
      # ❯ nix-store --add-fixed sha256 Mathematica_13.1.0_BNDL_LINUX.sh
      # /nix/store/jsnr55faq59xkq1az8isrs9rkzxdpxj2-Mathematica_13.1.0_BNDL_LINUX.sh
      unstable.blesh
      xscreensaver # note that this seems to require setup in home manager
      # for desktop gaming
      # simply setting config.programs.steam.enable to true adds stable steam
      unstable.heroic
      unstable.legendary-gl
      unstable.rare
      # unstable.protonup # automates updating GloriousEggroll's Proton-GE # currently borked, see: https://github.com/AUNaseef/protonup/issues/25
      unstable.protontricks
      unstable.proton-caller
      # unstable.bottles
      # unstable.gnutls # possibly needed for bottles to work correctly with battle.net launcher?
      unstable.discord
      unstable.boinc
      treesheets # freeform data organizer
      dunst # notification daemon for x11; wayland has "mako"; discord may crash without one of these
      # for retro gaming. this workaround was to fix the cores not installing properly
      (retroarch.override { cores = with libretro; [
        atari800 beetle-gba beetle-lynx beetle-ngp beetle-pce-fast beetle-pcfx beetle-psx beetle-psx-hw beetle-saturn beetle-snes beetle-supergrafx
        beetle-vb beetle-wswan bluemsx bsnes-mercury citra desmume desmume2015 dolphin dosbox eightyone fbalpha2012 fbneo fceumm flycast fmsx freeintv
        gambatte genesis-plus-gx gpsp gw handy hatari mame mame2000 mame2003 mame2003-plus mame2010 mame2015 mame2016 mesen meteor mgba mupen64plus
        neocd nestopia np2kai o2em opera parallel-n64 pcsx_rearmed picodrive play ppsspp prboom prosystem quicknes sameboy scummvm smsplus-gx snes9x
        snes9x2002 snes9x2005 snes9x2010 stella stella2014 tgbdual thepowdertoy tic80 vba-m vba-next vecx virtualjaguar yabause
      ]; })
      retroarch
      libretro.atari800 libretro.beetle-gba libretro.beetle-lynx libretro.beetle-ngp libretro.beetle-pce-fast libretro.beetle-pcfx libretro.beetle-psx libretro.beetle-psx-hw libretro.beetle-saturn libretro.beetle-snes libretro.beetle-supergrafx
      libretro.beetle-vb libretro.beetle-wswan libretro.bluemsx libretro.bsnes-mercury libretro.citra libretro.desmume libretro.desmume2015 libretro.dolphin libretro.dosbox libretro.eightyone libretro.fbalpha2012 libretro.fbneo libretro.fceumm libretro.flycast libretro.fmsx libretro.freeintv
      libretro.gambatte libretro.genesis-plus-gx libretro.gpsp libretro.gw libretro.handy libretro.hatari libretro.mame libretro.mame2000 libretro.mame2003 libretro.mame2003-plus libretro.mame2010 libretro.mame2015 libretro.mame2016 libretro.mesen libretro.meteor libretro.mgba libretro.mupen64plus
      libretro.neocd libretro.nestopia libretro.np2kai libretro.o2em libretro.opera libretro.parallel-n64 libretro.pcsx_rearmed libretro.picodrive libretro.play libretro.ppsspp libretro.prboom libretro.prosystem libretro.quicknes libretro.sameboy libretro.scummvm libretro.smsplus-gx libretro.snes9x
      libretro.snes9x2002 libretro.snes9x2005 libretro.snes9x2010 libretro.stella libretro.stella2014 libretro.tgbdual libretro.thepowdertoy libretro.tic80 libretro.vba-m libretro.vba-next libretro.vecx libretro.virtualjaguar libretro.yabause
      # for TUI and/or RPG games
      angband
      # zangband # error: Package ‘zangband-2.7.4b’ in ... is marked as broken, refusing to evaluate.
      tome2
      nethack
      unnethack
      harmonist
      hyperrogue
      crawl
      crawlTiles
      brogue
      meritous
      egoboo
      sil
      shattered-pixel-dungeon
      # end of TUI/RPG games list
      # other games & stuff
      xlife
      abuse
      pioneer
      the-powder-toy
      space-cadet-pinball
      airshipper # for veloren voxel game
      unvanquished
      endless-sky
      # tremulous # boooo, marked as broken :(
      torcs
      speed_dreams
      # media/video stuff
      unstable.audacity
      unstable.handbrake
      unstable.vlc
      unstable.shortwave # internet radio
      unstable.renoise # super cool mod-tracker-like audio app
      # gnomeExtensions.screen-lock # was incompatible with gnome version as of 7/22/2022
    ];
  };

  programs = {
    # Enable Steam
    # steam = {
    #   # enable = true;
    #   remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    #   # dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    # };
    ssh.startAgent = true;
  };

  # Fonts!
  fonts.fonts = with pkgs; [
    powerline-fonts
    inter # https://rsms.me/inter/
    google-fonts
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    fira-code
    fira-code-symbols
    font-awesome
    hack-font
    nerdfonts
    gentium # https://software.sil.org/gentium/
    eb-garamond # my favorite serif font
    atkinson-hyperlegible # possibly my favorite sans serif font; https://brailleinstitute.org/freefont
    inter # great helvetica clone; https://rsms.me/inter/
    key-rebel-moon # my favorite monospaced proprietary font with obfuscated name
    tech-alive # another favorite sans serif font with obfuscated name
  ];

  environment = {
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
      geary # email reader
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
      vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
      emacs
      bash
      bash-completion
      nix-bash-completions
      nixos-option
      file
      git
      duf # really nice disk usage TUI
      bind # provides nslookup etc
      # obtaining files:
      wget
      curl
      sshfs
      uget # a download manager GUI
      # various process viewers
      unstable.htop
      unstable.bpytop
      unstable.gotop
      unstable.atop
      unstable.iotop unstable.iotop-c
      unstable.ioping
      unstable.zenith # zoom-able charts
      unstable.nvtop # for GPU info
      # sysstat # not sure if needed, provides sa1 and sa2 commands meant to be run via crond?
      unstable.dstat # example use: dstat -cdnpmgs --top-bio --top-cpu --top-mem
      unstable.duc # disk usage visualization, highly configurable
      unstable.gdu # go disk usage
      baobab # radial treemap of disk usage
      # for showing off nixos:
      neofetch
      nix-tree
      hydra-check
      ripgrep # rg, the best grep
      fd # a better "find"
      rdfind # finds dupes, optionally acts on them
      unstable.mcfly # fantastic replacement for control-R history search
      exa # a better ls
      tokei # fast LOC counter
      p7zip
      latest.firefox-nightly-bin
      chromium
      unstable.wezterm
      gnome.gnome-tweaks # may give warning about being outdated? only shows it once, though?
      unstable.gnomeExtensions.appindicator
      unstable.gnomeExtensions.clipboard-indicator
      unstable.gnomeExtensions.freon
      unstable.gnomeExtensions.vitals
      unstable.gnomeExtensions.weather
      unstable.gnomeExtensions.sermon
      unstable.gnomeExtensions.pop-shell
      gnome.sushi
      gnome.dconf-editor
      gnome.zenity
      unstable.dconf2nix
      home-manager
      xorg.xbacklight
      # the following may be needed by vips but are optional
      # libjpeg
      # libexif
      # librsvg
      # poppler
      # libgsf
      # libtiff
      # fftw
      # lcms2
      # libpng
      # libimagequant
      # imagemagick
      # pango
      # orc
      # matio
      # cfitsio
      # libwebp
      # openexr
      # openjpeg
      # libjxl
      # openslide
      # libheif
      # zlib
      # end of vips deps
      unstable.vips # for my image manipulation stuff
      # unstable.rustup
      unstable.cargo
      unstable.rustc
      gcc
      gnumake
      # gnupg
      pkg-config
      # $%&* locales...
      glibcLocales
      # clang # removed due to collisions; install on project basis
      evince # gnome's document viewer (pdfs etc)
      groff # seems to be an undeclared dependency of evince...
      pciutils
      perf-tools
      vulkan-tools
      pv
      smartmontools
      gsmartcontrol
      efibootmgr
      # unstable.netdata # enabled via services.netdata.enable
      psmisc # provides killall, fuser, prtstat, pslog, pstree, peekfd
      hdparm
      cacert
      mkpasswd
      zfs
      polybar
      # stuff for my specific hardware
      system76-firmware
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
    };
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
      # we have 64 cores and 128 threads on this beast, so...
      # A value of "auto" may be permitted for 'max-jobs' (to use all available cores) but is not pure...
      # 'max-jobs' apparently also sets the number of possible concurrent downloads
      # 'cores' is like the "make -j" option; note that some packages don't like concurrent builds,
      # but that's their responsibility to limit themselves, in that case.
      # Current values may change and are being played with to find optimal combo
      max-jobs = 40;
      cores = 8;
      # use hardlinks to save space?
      auto-optimise-store = true;
      # flakes
      experimental-features = [ "nix-command" "flakes" ];
    };
    # automatically run gc?
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

}
