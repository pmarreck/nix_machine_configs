# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:
# add unstable channel definition for select packages, with unfree permitted
# Note that prior to this working you need to run:
# sudo nix-channel --add https://nixos.org/channels/nixos-unstable nixos-unstable
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
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Overlays
  nixpkgs.overlays = [
    # use native cpu optimizations
    # note: NOT PURE
    # (self: super: {
    #   stdenv = super.impureUseNativeOptimizations super.stdenv;
    # })
    # Firefox Nightly
    (import /home/pmarreck/Documents/nixpkgs-mozilla/firefox-overlay.nix)
  ];

  # Bootloader.
  boot = {
    cleanTmpDir = true;
    plymouth.enable = true;
    crashDump.enable = true;
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      efi.efiSysMountPoint = "/boot/efi";
    };
    # Boot using the latest kernel: pkgs.linuxPackages_latest
    # Boot with bcachefs test: pkgs.linuxPackages_testing_bcachefs
    kernelPackages = pkgs.linuxPackages_latest; #pkgs.linuxPackages_rpi4

    kernel.sysctl = {
      "vm.swappiness" = 90;
      "vm.vfs_cache_pressure" = 150;
      "vm.dirty_ratio" = 1;
      "vm.dirty_background_ratio" = 2;
      "kernel.task_delayacct" = 1; # so iotop/iotop-c can work; may add latency
    };

    kernelParams = [ "cgroup_no_v1=all" "systemd.unified_cgroup_hierarchy=yes" ];
  };

  # Networking details
  networking = {
    hostName = "nixos"; # Define your hostname.
    # Enable networking
    networkmanager.enable = true;
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    # Configure network proxy if necessary
    #   proxy.default = "http://user:password@proxy:port/";
    #   proxy.noProxy = "127.0.0.1,localhost,internal.domain";
    # Boot optimizations regarding networking:
    # don't wait for an ip
    dhcpcd.wait = "background";
    # don't check if IP is already taken by another device on the network
    dhcpcd.extraConfig = "noarp";
    # fix for https://github.com/NixOS/nix/issues/5441
    hosts = {
      "127.0.0.1" = [ "this.pre-initializes.the.dns.resolvers.invalid." ];
    };
  };

  systemd = {
    services = {
      systemd-journal-flush.enable = false; # had super high disk ute in jbd2
      NetworkManager-wait-online.enable = false;
      nix-daemon.serviceConfig = {
        CPUWeight = 50;
        IOWeight = 50;
      };
      # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
      "getty@tty1".enable = false;
      "autovt@tty1".enable = false;
    };
    extraConfig = ''
      DefaultCPUAccounting=yes
      DefaultMemoryAccounting=yes
      DefaultIOAccounting=yes
    '';
    user.extraConfig = ''
      DefaultCPUAccounting=yes
      DefaultMemoryAccounting=yes
      DefaultIOAccounting=yes
    '';
    services."user@".serviceConfig.Delegate = true;
  };

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Allow unfree packages (necessary for firefox and steam etc)
  nixpkgs.config = {
    allowUnfree = true;
    # the following didn't work because "lib" is not defined:
    # allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    #   "steam"
    #   "steam-original"
    #   "steam-runtime"
    # ];
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
      # > gsettings list-recursively org.gnome.settings-daemon.plugins
      desktopManager.gnome.extraGSettingsOverrides = ''
        [org.gnome.desktop.wm.preferences]
        button-layout=':minimize,maximize,close'

        [org.gnome.settings-daemon.plugins.color]
        night-light-enabled=true
        night-light-temperature=2500
        night-light-schedule-automatic=true
      '';
      # wayland wonky with nvidia, still
      displayManager.gdm.wayland = false;
      # use nvidia card for xserver
      videoDrivers = ["nvidia"];
      # Configure keymap in X11
      layout = "us";
      xkbVariant = "";
      # Enable automatic login for the user.
      displayManager.autoLogin.enable = false;
      displayManager.autoLogin.user = "pmarreck";
      # Enable touchpad support (enabled default in most desktopManager).
      # libinput.enable = true;
    };
    # the following 2 lines may no longer be necessary now
    # dbus.packages = [ pkgs.gnome3.dconf ];
    # udev.packages = [ pkgs.gnome3.gnome-settings-daemon ];

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
      Storage=volatile
      SystemMaxFileSize=30M
      SystemMaxFiles=5
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
    postgresql = {
      enable = true;
      package = pkgs.postgresql_13;
      enableTCPIP = true;
      authentication = pkgs.lib.mkOverride 10 ''
        local all all trust
        host all all 127.0.0.1/32 trust
        host all all ::1/128 trust
      '';
      initialScript = pkgs.writeText "backend-initScript" ''
        CREATE ROLE postgres WITH LOGIN PASSWORD 'postgres' CREATEDB;
        CREATE DATABASE postgres;
        CREATE DATABASE mpnetwork;
        GRANT ALL PRIVILEGES ON DATABASE postgres TO postgres;
        GRANT ALL PRIVILEGES ON DATABASE mpnetwork TO postgres;
      '';
    };
  };

  # Configure my 3D card correctly (hopefully!)
  # ...Actually, simply setting config.programs.steam.enable = true does these:
  # hardware.opengl = {
  #   enable = true;
  #   # see discussion: https://app.bountysource.com/issues/74599012-nixos-don-t-set-ld_library_path-for-graphics-drivers-that-don-t-need-it
  #   # setLdLibraryPath = true;
  #   driSupport32Bit = true;
  # };
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
  # hardware.nvidia.powerManagement.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.pmarreck = {
    isNormalUser = true;
    description = "Peter Marreck";
    extraGroups = [ "networkmanager" "wheel" "tty" ];
    packages = with pkgs; [
      unstable.elixir
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
      xscreensaver # note that this seems to require setup in home manager
      # for desktop gaming
      # steam # your kernel, video driver and steam all have to line up, sigh
      # simply setting config.programs.steam.enable to true adds stable steam
      unstable.heroic
      protonup # automates updating GloriousEggroll's Proton-GE
      vlc
      unstable.discord
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
      # gnomeExtensions.screen-lock # was incompatible with gnome version as of 7/22/2022
    ];
  };

  # Enable Steam
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    # dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
  };

  # Fonts!
  fonts.fonts = with pkgs; [
    powerline-fonts
    inter
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    fira-code
    fira-code-symbols
    font-awesome
    hack-font
    nerdfonts
    key-rebel-moon # my custom proprietary font with obfuscated name
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
      evince # document viewer
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
      wget
      curl
      bash
      bash-completion
      nix-bash-completions
      file
      git
      duf
      htop
      unstable.bpytop
      gotop
      neofetch
      ripgrep
      fd
      unstable.mcfly
      exa
      tokei
      latest.firefox-nightly-bin
      chromium
      unstable.wezterm
      gnomeExtensions.appindicator
      home-manager
      xorg.xbacklight
      # the following may be needed by vips but are optional
      libjpeg
      libexif
      librsvg
      poppler
      libgsf
      libtiff
      fftw
      lcms2
      libpng
      libimagequant
      imagemagick
      pango
      orc
      matio
      cfitsio
      libwebp
      openexr
      openjpeg
      libjxl
      openslide
      libheif
      zlib
      # end of vips deps
      unstable.vips # for my image manipulation stuff
      # unstable.rustup
      unstable.cargo
      unstable.rustc
      gcc
      gnumake
      gnupg
      pkg-config
      # $%&* locales...
      glibcLocales
      # clang # removed due to collisions; install on project basis
      pciutils
      perf-tools
      atop
      unstable.iotop unstable.iotop-c
      ioping
      sysstat
      dstat
      cacert
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
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Don't ask for my password quite as often
  security.sudo.extraConfig = "Defaults timestamp_timeout=60";


  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  ##### System level configs

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "22.05"; # Did you read the comment?

  # autoupgrade?
  system.autoUpgrade.enable = false;
  system.autoUpgrade.allowReboot = false; # reboot if kernel changes?
  system.autoUpgrade.channel = https://nixos.org/channels/nixos-22.05;

  ### Nix settings
  nix = {
    settings = {
      # we have 128 cores on this beast, so...
      # A value of "auto" may be permitted for max-jobs but is not pure...
      # Cores is like the make -j option, and some packages don't like concurrent builds... sigh
      max-jobs = "auto";
      # nix.settings.cores = 4; # "option does not exist"??
      cores = 64;
      # use hardlinks to save space?
      auto-optimise-store = true;
    };
    # automatically run gc?
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

}
