# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:
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
  elixir = pkgs.beam.packages.erlangR26.elixir_1_16;
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
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      <nixos-hardware/framework/16-inch/7040-amd>
    ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "electron-25.9.0"
    "mailspring-1.12.0" # CVE-2023-4863
  ];

  # for ollama acceleration
  nixpkgs.config.rocmSupport = true;

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
    #(self: super: { nix-direnv = super.nix-direnv.override { enableFlakes = true; }; } )
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # AMD support
  boot.kernelModules = [ "amdgpu" "radeon" ];
  boot.kernelParams = [ "radeon.si_support=0" "amdgpu.si_support=1" "radeon.cik_support=0" "amdgpu.cik_support=1" ];
  # boot.extraModulePackages = with config.boot.kernelPackages; [ linuxPackages.amdgpu ];
  boot.extraModulePackages = [ pkgs.linuxKernel.packages.linux_6_6.amdgpu-pro ];
  hardware.enableAllFirmware = true;


  networking.hostName = "framework-nixos"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # ollama service
  services.ollama.enable = true;

  # fingerprint reader
  # services.fprintd.enable = true; # enabled by a hardare support include above
  # remember to do:
  # sudo fprintd-enroll $USER

  # ppd
  services.power-profiles-daemon.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # framework laptop
  services.fwupd.enable = true;

  # Configure keymap in X11
  services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    wireplumber.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true; 
    pulse.enable = true; # For PulseAudio emulation
    jack.enable = true; # If you need JACK support
  };
  security.rtkit.enable = true; # Gives realtime priority

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
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
      glxinfo
      clinfo
      ocl-icd # for opencl
      patchelf # for fixing up binaries in nix
      stable.cudaPackages.cudatoolkit # for tensorflow
      mono # for C#/.NET stuff
      unstable.vscode # nice gui editor
      unstable.zed-editor # code editor
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
      # polychromatic # razer mouse/keyboard config tool
      master.whatsapp-for-linux # whatsapp desktop clientrom
      master.signal-desktop # signal desktop client
      telegram-desktop # chat app
      transmission-gtk # torrent client
      bfs # better, breadth-first search
      nms # No More Secrets, a recreation of the live decryption effect from the famous hacker movie "Sneakers"
      boinc # distributed computing
      treesheets # freeform data organizer
      flameshot # screenshot tool
      shotwell # photo organizer like iPhoto
      darktable # photo editor # forced stable on 1/24/2023 due to build failure on unstable
      krita # drawing program
      stable.gimp-with-plugins # drawing program # forced stable on 1/20/2023 due to build failure on unstable
      dunst # notification daemon for x11; wayland has "mako"; discord may crash without one of these
      unstable.ollama # playing with LLM's
      # bluemail # email client # doesn't currently work...
      mailspring # nice open-source email client
      # thunderbird # the venerable email client
      # evolutionWithPlugins # email client
      recoll # full-text search tool
      moar # a better "less"
      sequeler # gui for postgresql/mariadb/mysql/sqlite; very nice # downgraded to stable 6/13/2023 due to build failure on unstable
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
        # stable.tome2 # roguelike # build errored 5/12/2024
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
      # stable.speed_dreams # build failed 5/12/2024
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
      # master.renoise # super cool mod-tracker-like audio app # unfortunately, d/l fails on 24.05 currently (7/17/2024)
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
    # Enable Steam
    steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    };
    ssh = {
      startAgent = true;
      extraConfig = ''
        Host *
          AddKeysToAgent yes
          IdentityFile ~/.ssh/id_ed25519
      '';
    };
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

  # List packages installed in system profile. To search, run:
  # $ nix search wget
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
      # busybox # for a ton of basic unix utils... do not enable, it covers too much and breaks too much stuff
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
      master.yt-dlp # for downloading videos from youtube and other sites
      # ytmdl # for downloading music from youtube # build fail 5/12/2024
      clipgrab # for downloading videos from youtube and other sites
      sshfs # for mounting remote filesystems
      cachix # for downloading pre-built binaries
      comma # for trying out software, see "let" section above
      hwinfo # hardware info
      uget # a download manager GUI
      obsidian # a note-taking app based on plain markdown files
      ## Timers
      gnome-solanum # timer GUI
      gedit # gnome text editor
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
      gnomeExtensions.night-theme-switcher # for automatically switching between light and dark themes
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
      # pinentry # for gpg/gnupg password entry GUI. why does it not install this itself? ah, found out...
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
      # openrazer-daemon # for razer stuff
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
      #system76-firmware # for system76 firmware updates
    ];

    variables = {
      EDITOR = "code";
      BROWSER = "firefox";
      # fix for this curl issue with https requests: https://github.com/NixOS/nixpkgs/issues/148686
      #CURL_CA_BUNDLE = "/etc/pki/tls/certs/ca-bundle.crt"; # this is the value of $SSL_CERT_FILE ; obviously this is brittle and may change
      # ^ May be fixed by adding `cacert` to systemPackages; haven't checked yet though
      # McFly config: https://github.com/cantino/mcfly
      MCFLY_INTERFACE_VIEW = "BOTTOM";
      MCFLY_RESULTS = "50";
      MCFLY_FUZZY = "2";
      NIXPKGS_ALLOW_UNFREE = "1";
      # friggin' keeps picking the wrong video card!!
      # DXVK_FILTER_DEVICE_NAME = "GeForce RTX 3080 Ti";
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
      STEAM_EXTRA_COMPAT_TOOLS_PATHS = "\${HOME}/.steam/root/compatibilitytools.d";
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
    pinentryPackage = pkgs.pinentry-gnome3;
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "23.11"; # Did you read the comment?

}

