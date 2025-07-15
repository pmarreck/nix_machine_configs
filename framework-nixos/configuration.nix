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
  # roc is dynamically compiled, so it's not usable in NixOS yet
  # roc = (import (pkgs.fetchFromGitHub {
  #   owner = "roc-lang";
  #   repo = "roc";
  #   rev = "nightly";
  #   hash = "sha256-qm045v41H3y1pUF1Zyv+EqF+UQRmFBgiT0QwcFpOyvY=";
  # })).default;
  # nix-software-center = (import (pkgs.fetchFromGitHub {
  #   owner = "vlinkz";
  #   repo = "nix-software-center";
  #   rev = "0.1.1";
  #   sha256 = "0frigabszyfkphfbsniaa1d546zm8a2gx0cqvk2fr2qfa71kd41n";
  # })) {};
  # custom_python3 = ((pkgs.python312.override {
  #     enableOptimizations = true;
  #     reproducibleBuild = false;
  #     # self = custom_python3;
  #   }).withPackages (ps: with ps; [
  #   # (zfec.overrideAttrs (old: {
  #   #   src = /home/pmarreck/Documents/zfec;
  #   # }))
  #   pip
  #   toolz
  #   requests # for requests
  #   pillow  # for image processing
  #   virtualenv
  #   tkinter # for tkinter
  #   pytest # for testing
  #   pygments # syntax highlighting for 565 languages in terminal
  #   pandas # for data analysis
  #   urllib3 # for requests
  #   nltk  # natural language toolkit
  #   torch # for machine learning
  #   # torchvision
  #   # torchaudio-bin
  #   sentencepiece
  #   numpy
  # ])).override (args: { ignoreCollisions = true; });
  luajitUserPackages = with pkgs.luajitPackages; {
    inherit alt-getopt basexx busted cjson lpeg lua_cliargs luabitop luacheck luafilesystem luarocks luasocket luasystem moonscript nfd penlight tl;
  };

  getLuaPath = pkg: [
    "${pkg}/share/lua/5.1/?.lua"
    "${pkg}/share/lua/5.1/?/init.lua"
  ];

  getLuaCPath = pkg: [
    "${pkg}/lib/lua/5.1/?.so"
  ];

  luaPath = lib.concatStringsSep ";" (
    (lib.flatten (lib.mapAttrsToList (name: pkg: getLuaPath pkg) luajitUserPackages)) ++ [
      "./?.lua"
      "./?/init.lua"
    ]
  );

  luaCPath = lib.concatStringsSep ";" (
    (lib.flatten (lib.mapAttrsToList (name: pkg: getLuaCPath pkg) luajitUserPackages)) ++ [
      "./?.so"
    ]
  );
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
  services.xserver = {
    enable = true;
    dpi = 189;  # Adjust this value as needed for your desired scale
    # Configure keymap in X11
    xkb = {
      layout = "us";
      # options = "eurosign:e,caps:escape";
    };
  };

  # ollama service
  services.ollama.enable = true;

  # fingerprint reader
  services.fprintd.enable = false;
  # remember to do:
  # sudo fprintd-enroll $USER

  # ppd
  services.power-profiles-daemon.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # framework laptop
  services.fwupd.enable = true;

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
      # bottles
      # evolutionWithPlugins # email client
      # gnomeExtensions.screen-lock # was incompatible with gnome version as of 7/22/2022
      # gnutls # possibly needed for bottles to work correctly with battle.net launcher?
      # legendary-gl
      # lutris # It always struck me as wonky, but I'm including this game launcher for now. EDIT: Nope, still wonky AF. Bye.
      # markets # stock market watcher # went defunct in march 2023: https://github.com/tomasz-oponowicz/markets
      # master.renoise # super cool mod-tracker-like audio app # unfortunately, d/l fails on 24.05 currently (7/17/2024)
      # numworks-epsilon # whoa, cool calc! # disabled due to disuse, and troubleshooting an issue
      # polychromatic # razer mouse/keyboard config tool
      # protonup # automates updating GloriousEggroll's Proton-GE # currently borked, see: https://github.com/AUNaseef/protonup/issues/25
      # razergenie # razer mouse/keyboard config tool. disabled because seems lamer than polychromatic
      # space-cadet-pinball # nostalgia # disabled on 10/20/2024 due to build failure on stable/unstable
      # stable.speed_dreams # build failed 5/12/2024
      # stable.tome2 # roguelike # build errored 5/12/2024
      # thunderbird # the venerable email client
      # tremulous # boooo, marked as broken :(
      # zangband # error: Package ‘zangband-2.7.4b’ in ... is marked as broken, refusing to evaluate.
      abuse # classic side-scrolling shooter customizable with LISP
      # aider-chat # AI code editing TUI
      airshipper # for veloren voxel game
      almonds # TUI fractal viewer
      angband # A classic roguelike dungeon exploration game
      asciinema # record terminal sessions
      aspell # GNU spell checker
      # atac # Postman, but as a TUI. API client.
      audacious # audio player
      audacious-plugins # audio player plugins
      audacity # audio editor
      bat # A cat clone with syntax highlighting and git integration
      bfs # better, breadth-first search
      blesh # Bash line editor with syntax highlighting
      bluemail # email client # doesn't currently work...
      boinc # distributed computing
      bottom # Like top but bottomer
      brogue # roguelike
      browsh # graphical web browser in the terminal
      unstable.capstone # Advanced disassembly library
      master.claude-code # An agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster
      clinfo
      colordiff # A tool to colorize diff output
      crawl # roguelike
      crawlTiles # roguelike
      crystal # Compiled language with Ruby-like syntax and type inference
      csvkit # Various tools for working with CSV files such as csvlook, csvcut, csvsort, csvgrep, csvjoin, csvstat, csvsql, etc.
      curlpp # for curl bindings in C++
      darktable # photo editor # forced stable on 1/24/2023 due to build failure on unstable
      delta #syntax highlighter for git
      dirb # Web content scanner for finding hidden files/directories
      discord # chat app for gamers
      drawing # drawing program
      dunst # notification daemon for x11; wayland has "mako"; discord may crash without one of these
      egoboo # dungeon crawler
      endless-sky # space exploration game
      exiftool # Tool to read, write and edit EXIF meta information
      fclones # Efficient duplicate file finder
      ffmpeg # A complete solution to record, convert and stream audio and video
      figlet # Program for making large letters out of ordinary text
      filezilla # it's no Transmit.app, but it'll do
      flameshot # screenshot tool
      fontconfig # Library for configuring and customizing font access
      fortune # fortune cookie
      free42 # hp-42S reverse-engineered from the ground up
      # frogmouth # A Markdown browser TUI # disabled due to build failure thanks to 'textual' dependency invalidation
      fsearch # file search GUI
      fzf # fuzzy finder
      fzy # fuzzy finder that's faster/better than fzf
      galculator # calculator GUI
      gamehub # game launcher
      gawkInteractive # GNU awk with readline support and better error messages
      gcc # compiler for C
      ghostscript # Ghostscript is an interpreter for the PostScript language and PDF files
      glow # markdown viewer TUI
      glxinfo
      gmp # GNU Multiple Precision Arithmetic Library
      gravit # gravity simulator
      gthumb # image viewer
      harmonist # roguelike
      hyperfine # command-line benchmarking tool
      hyperrogue # roguelike
      inkscape-with-extensions # Vector graphics editor with extensions
      jazz2 # open source reimplementation of classic Jazz Jackrabbit 2 game
      jetbrains.datagrip # gui for postgresql/mariadb/mysql/sqlite
      jq # json query
      unstable.jjui # A TUI for Jujutsu VCS
      unstable.jujutsu # A Git-compatible DVCS that is both simple and powerful
      krita # drawing program
      less # GNU terminal based program for paging text files or output
      libheif # ISO/IEC 23008-12:2017 HEIF file format decoder and encoder
      libjxl # JPEG XL image format reference implementation
      libwebp # Library and tools for the WebP image format
      lightspark # Flash (ActionScript 3) runner
      mailspring # nice open-source email client
      master.gum # looks like a super cool TUI tool for shell scripts: https://github.com/charmbracelet/gum
      master.signal-desktop # signal desktop client
      master.whatsapp-for-linux # whatsapp desktop clientrom
      meritous # platformer
      moar # a better "less"
      mono # for C#/.NET stuff
      nasc # "do maths like a normal person", it says. I'm intrigued.
      nethack # roguelike
      newtonwars # missile game with gravity as a core element
      nim # Nim programming language
      nixd # nix language server
      nmap # Network exploration tool and security scanner
      nms # No More Secrets, a recreation of the live decryption effect from the famous hacker movie "Sneakers"
      nnn # Terminal file manager
      ocl-icd # for opencl
      ocrmypdf # Adds an OCR text layer to scanned PDF files, allowing them to be searched
      odin # A programming language for creating multi-platform apps
      opencl-clhpp # for opencl
      openssl # security
      parallel # parallelize shell commands
      patchelf # for fixing up binaries in nix
      peco # TUI fuzzy finder and selector
      pioneer # space exploration game
      pkg-config # for compiling C/C++
      poppler_utils # PDF tools
      presenterm # A markdown-based terminal slideshow tool
      procps # Utilities that give information about processes
      proton-caller # automates launching proton games
      python312Packages.pygments # Syntax highlighting library
      python311Packages.conda # python package manager (ew. but need it for LLM's)
      python311Packages.pandas # for data analysis
      python311Packages.pillow # for image processing
      python311Packages.pip # for pip
      python311Packages.pygments # syntax highlighting for 565 languages in terminal
      python311Packages.python # python interpreter
      python311Packages.tkinter # for tkinter
      python311Packages.torch-bin
      python311Packages.torchaudio-bin
      python311Packages.torchvision-bin
      python311Packages.virtualenv # for virtualenv
      qalculate-gtk # very cool calculator
      qFlipper # for Flipper Zero
      qpdf # C++ library and set of programs that inspect and manipulate the structure of PDF files
      rclone # rsync for cloud storage
      rclone-browser # GUI for rclone
      recoll # full-text search tool
      rhythmbox # audio player
      ruffle # Flash (soon ActionScript 3) runner
      sampler # TUI for shell commands execution, visualization and alerting
      sc-im # Spreadsheet Calculator Improved - terminal spreadsheet program
      scorched3d # played the original version a lot in the military
      sd # Intuitive find & replace CLI tool
      sequeler # gui for postgresql/mariadb/mysql/sqlite; very nice # downgraded to stable 6/13/2023 due to build failure on unstable
      shattered-pixel-dungeon # roguelike
      shortwave # internet radio
      shotwell # photo organizer like iPhoto
      sil # roguelike
      slack # the chat app du jour
      sourceHighlight # Source code renderer with syntax highlighting
      speedread # speed reading
      speedtest-cli
      unstable.cudaPackages.cudatoolkit # for tensorflow
      unstable.curl-impersonate # Command-line tool to impersonate a browser
      stable.gimp-with-plugins # drawing program # forced stable on 1/20/2023 due to build failure on unstable
      stable.gitkraken # git gui (as opposed to "git gud" I guess) # downgraded to stable 10/20/2024 due to build failure
      stable.handbrake # forced stable on 1/20/2023 due to build failure on unstable with ffmpeg
      stable.heroic # heroic game launcher # forced stable on 4/13/2023 due to build failure on unstable
      # unstable.nheko # matrix client # forced stable on 6/28/2023 due to build failure on unstable # commented out due to security issue in libolm: CVE-2024-4519[123
      stable.opensnitch # littlesnitch for linux. forced stable on 2/16/2023 due to build failure on unstable
      stable.opensnitch-ui
      # master.oterm # Ollama chat TUI, disabled due to deprecation of textual
      stable.pbzip2 # Parallel implementation of bzip2 (pinned to stable)
      stable.rare # rare is a game launcher for epic games store # forced stable on 2/16/2023 due to build failure on unstable
      stable.ripgrep-all # ripgrep-all is a wrapper around ripgrep, fd, and git that allows you to search through your codebase using ripgrep syntax.
      stable.spotify # forced stable on 2/16/2023 due to build failure on unstable
      stable.spotifyd # spotify streamer daemon
      starship # cool prompt
      taoup # The Tao of Unix Programming
      telegram-desktop # chat app
      unstable.television # Blazingly fast general purpose fuzzy finder TUI
      tesseract # OCR
      the-powder-toy # sandbox game
      ticker # stock market watcher, to replace the "markets" GUI
      torcs # racing game
      transmission-gtk # torrent client
      treesheets # freeform data organizer
      trippy # Network diagnostic tool TUI
      trufflehog # scans github repos for possible secrets checked in by accident
      unnethack # roguelike
      unstable.chatgpt-cli # CLI for ChatGPT
      unstable.clementine # audio player
      unstable.csvquote # Wraps each field in a CSV file in quotes and escapes existing quotes and commas in the fields
      # unstable.fluffychat # re-enabled 4/11/2023 after apparent dependency bugfix # disabled again due to CVE vulns in its encryption libs
      unstable.ghostty # mitchell hashimoto's new Zig-written cross-platform terminal emulator
      unstable.gnome-builder # code editor
      unstable.micro # sort of an enhanced nano
      unstable.o # Simple text editor/IDE intentionally limited to VT100; https://github.com/xyproto/o
      master.ollama # playing with LLM's
      unstable.vscode # nice gui editor
      unstable.zed-editor # code editor
      unvanquished # FPS
      visidata # Terminal TUI spreadsheet multitool for discovering and arranging data
      vsce # Visual Studio Code extensions manager/tooling
      vlc # video player
      wdiff # A front end to diff for comparing files on a word per word basis
      unstable.windsurf # the agentic AI code editor
      unstable.wiper # TUI tool that pinpoints large folders, scans directories and shows how your space is used
      xaos # smooth fractal explorer
      xlife # cellular automata
      xscreensaver # note that this seems to require setup in home manager
      zoom-us # the chinese spy network
      ## for retro gaming. this workaround was to fix the cores not installing properly
      ## (retroarch.override { cores = with libretro; [
      ##   atari800 beetle-gba beetle-lynx beetle-ngp beetle-pce-fast beetle-pcfx beetle-psx beetle-psx-hw beetle-saturn beetle-snes beetle-supergrafx
      ##   beetle-vb beetle-wswan bluemsx bsnes-mercury citra desmume desmume2015 dolphin dosbox eightyone fbalpha2012 fbneo fceumm flycast fmsx freeintv
      ##   gambatte genesis-plus-gx gpsp gw handy hatari mame mame2000 mame2003 mame2003-plus mame2010 mame2015 mame2016 mesen meteor mgba mupen64plus
      ##   neocd nestopia np2kai o2em opera parallel-n64 picodrive play ppsspp prboom prosystem quicknes sameboy scummvm smsplus-gx snes9x
      ##   snes9x2002 snes9x2005 snes9x2010 stella stella2014 tgbdual thepowdertoy tic80 vba-m vba-next vecx virtualjaguar yabause
      ##   # pcsx-rearmed
      ## ]; })
      ## retroarch
      ## (with libretro; [
      ##   atari800 beetle-gba beetle-lynx beetle-ngp beetle-pce-fast beetle-pcfx beetle-psx beetle-psx-hw beetle-saturn beetle-snes beetle-supergrafx
      ##   beetle-vb beetle-wswan bluemsx bsnes-mercury citra desmume desmume2015 dolphin dosbox eightyone fbalpha2012 fbneo fceumm flycast fmsx freeintv
      ##   gambatte genesis-plus-gx gpsp gw handy hatari mame mame2000 mame2003 mame2003-plus mame2010 mame2015 mame2016 mesen meteor mgba mupen64plus
      ##   neocd nestopia np2kai o2em opera parallel-n64 picodrive play ppsspp prboom prosystem quicknes sameboy scummvm smsplus-gx snes9x
      ##   snes9x2002 snes9x2005 snes9x2010 stella stella2014 tgbdual thepowdertoy tic80 vba-m vba-next vecx virtualjaguar yabause
      ##   # pcsx-rearmed
      ## ])
    ];
  };

  programs = {
    # Enable Steam
    steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
      extraCompatPackages = with pkgs; [
        proton-ge-bin # Compatibility tool for Steam Play based on Wine and additional components. (This is intended for use in the `programs.steam.extraCompatPackages` option only.) 
      ];
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
      atkinson-hyperlegible # possibly my favorite sans serif font; https://brailleinstitute.org/freefont
      corefonts
      eb-garamond # my favorite serif font
      fira-code
      fira-code-symbols
      font-awesome
      gentium # https://software.sil.org/gentium/
      google-fonts
      hack-font
      hasklig # source code pro plus more ligatures, https://github.com/i-tu/Hasklig
      inconsolata
      inter # great helvetica clone; https://rsms.me/inter/
      key-rebel-moon # my favorite monospaced proprietary font with obfuscated name
      liberation_ttf
      nerdfonts
      noto-fonts
      noto-fonts-cjk
      noto-fonts-emoji
      powerline-fonts
      source-code-pro
      tech-alive # another favorite sans serif font with obfuscated name
      terminus-nerdfont
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
      (wineWowPackages.unstableFull.override { wineRelease = "staging"; mingwSupport = true; })
      # (callPackage ./cursor.nix {}) # for cursor editor
      # bash-completion # Programmable completion for the bash shell # note: caused problems
      # bash-preexec # Bash preexec and precmd functions # disabled since it's pulled in via a dotfile function now
      # busybox # for a ton of basic unix utils... do not enable, it covers too much and breaks too much stuff
      # clang # removed due to collisions; install on project basis
      # code-cursor
      # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
      # gnomeExtensions.clipboard-indicator # "incompatible with current Gnome version"
      # gnomeExtensions.cpufreq # incompatible with gnome version as of 11/21/2022
      # gnomeExtensions.dash-to-dock-animator # "incompatible with current Gnome version"
      # gnomeExtensions.dash-to-dock-toggle # "incompatible with current Gnome version"
      # gnomeExtensions.gamemode # "incompatible with current Gnome version"
      # gnomeExtensions.hide-top-bar # may be leading to instability with alt-tabbing freezing the GUI from fullscreen apps (games)
      # gnomeExtensions.random-wallpaper # "incompatible with current Gnome version"
      # gnomeExtensions.scrovol # doesn't work with latest gnome
      # gnomeExtensions.sermon
      # gnomeExtensions.toggle-imwheel # for mouse wheel scrolling # "incompatible with current Gnome version"
      # gnomeExtensions.user-themes # "incompatible with current Gnome version"
      # gnomeExtensions.weather # doesn't work with latest gnome
      # gnomeExtensions.what-watch # analog floating clock # "incompatible with current Gnome version"
      # gnupg # installed separately in config elsewhere
      # lsb-release # sys info # nah, do "source /etc/os-release; echo $PRETTY_NAME" instead
      # netdata # enabled via services.netdata.enable
      # nix-software-center # for installing nix packages via a GUI
      # openrazer-daemon # for razer stuff
      # pinentry # for gpg/gnupg password entry GUI. why does it not install this itself? ah, found out... # https://github.com/NixOS/nixpkgs/commit/3d832dee59ed0338db4afb83b4c481a062163771
      # roc # Fast. Friendly. Functional.
      # sysstat # not sure if needed, provides sa1 and sa2 commands meant to be run via crond?
      # ytmdl # for downloading music from youtube # build fail 5/12/2024
      alacritty # a super fast terminal
      alsa-utils # for alsa sound utilities
      appimage-run # to run appimages
      ascii # commandline ascii chart
      atop # advanced top
      atuin # a better history search, with sync and fuzzy search
      baobab # radial treemap of disk usage
      bashInteractive # The venerable GNU Bourne Again shell
      bc # calculator (also a basic language... possibly useful for education?)
      bind # provides nslookup etc
      bmon # network bandwidth monitor
      bottom # a modern alternative to top
      btop # better than htop
      bucklespring # for keyboard sounds
      cacert # for curl certificate verification
      cachix # for downloading pre-built binaries
      cargo # rust package manager
      chez # Chez Scheme (useful for idris)
      chromium # like chrome but without the google
      clipgrab # for downloading videos from youtube and other sites
      comma # for trying out software, see "let" section above
      conky # system monitor
      cool-retro-term # a retro terminal emulator
      coreutils-prefixed # most gnu utils prefixed with "g" to disambiguate them in cross platform scripts that make buggy assumptions
      cosmocc # Cosmopolitan (Actually Portable Executable) C/C++ toolchain; use via CC=cosmocc, CXX=cosmoc++
      cowsay # a classic
      curl # curl is better than wget because it supports more protocols
      dcfldd # dd with progress bar and inline hash verification
      dconf2nix # for converting dconf settings to nix
      direnv # for loading environment variables from .env and .envrc files
      dmd # Official reference compiler for d-lang
      dstat # example use: dstat -cdnpmgs --top-bio --top-cpu --top-mem
      duc # disk usage visualization, highly configurable
      duf # really nice disk usage TUI
      efibootmgr # for managing EFI boot entries
      emacs # it's no vim
      et # A minimal (egg) timer TUI based on libnotify
      evince # gnome's document viewer (pdfs etc)
      eza # A modern replacement for ls (fork of exa)
      fd # a better "find"
      file # file type identification
      frawk # An efficient AWK-like language
      fzf # fuzzy finder
      gcc # C compiler
      gdu # go disk usage, great way to visualize disk usage
      gedit # gnome text editor
      ghostscript # PostScript interpreter (mainline version)
      git # the stupid content tracker
      git-lfs # git large file storage (for large AI models, usually)
      glib # seems to be an undeclared dependency of some gnome tweaks such as Night Theme Switcher
      glibcLocales # for locales
      gmp # GNU Multiple Precision Arithmetic Library
      gnome-solanum # timer GUI
      gnome.dconf-editor # for editing gnome settings
      gnome.gnome-tweaks # may give warning about being outdated? only shows it once, though?
      gnome.sushi # file previewer (just hit spacebar in Gnome Files)
      gnome.zenity # for zenity, a GUI dialog box tool
      gnomeExtensions.appindicator # for system tray icons
      gnomeExtensions.dash-to-dock # for moving the dock to the bottom
      gnomeExtensions.freon # for monitoring CPU and GPU temps
      gnomeExtensions.lock-keys # for showing caps lock etc
      gnomeExtensions.miniview # for quick window previews
      gnomeExtensions.night-theme-switcher # for automatically switching between light and dark themes
      gnomeExtensions.pop-shell # for tiling windows
      gnomeExtensions.rclone-manager # adds an indicator to the top panel so you can manage the rclone profiles configured in your system
      gnomeExtensions.vitals # for monitoring CPU and GPU temps
      gnugrep # GNU implementation of the grep command
      gnumake # make
      gnused # GNU sed, a batch stream editor
      gotop # a terminal based graphical activity monitor inspired by gtop and vtop
      gping # ping with a graph
      gptfdisk # for gdisk
      groff # seems to be an undeclared dependency of evince...
      gsmartcontrol
      has # for verifying the availability and version of executables
      hdparm # for hard drive info
      home-manager # for managing user settings in Nix
      htop # better than top
      hwinfo # hardware info
      hydra-check # show hydra status
      idris2 # Idris2 functional statically-typed programming language that looks cool and compiles to C
      imagemagick # for converting images
      imwheel # for mouse wheel scrolling
      inetutils # provides ping telnet etc
      inotify-tools # for watching files programmatically
      ioping # disk latency tester
      iotop iotop-c # iotop-c is a fork of iotop with a curses interface
      kitty # another nice terminal emulator
      kmon # kernel module monitor
      latest.firefox-nightly-bin # firefox
      ldc # d-lang LLVM compiler
      libreoffice-fresh # needed for gnome sushi to preview Office files, otherwise *big hang*. No idea if I picked the right LibreOffice as there's like a dozen variants and NO docs about this.
      lsof # for listing open files and ports
      luajit # High-performance JIT compiler for Lua 5.1
      lz4 # Extremely fast compression algorithm
      master.visidata # https://github.com/saulpw/visidata
      master.yt-dlp # for downloading videos from youtube and other sites
      mcfly # fantastic replacement for control-R history search
      meld # visual diff and merge tool
      mkpasswd # for generating passwords
      monitor # yet another sexy system monitor
      mpv # media player
      murex # awesome looking shell, see murex.rocks
      ncdu # "ncurses du (disk usage)"
      neofetch # system info
      nethogs # network bandwidth monitor
      nitrogen # wallpaper/desktop image manager
      nix-bash-completions # bash completions for nix
      nix-direnv # direnv integration for nix
      nix-index # also provides nix-locate
      nix-tree # show nixpkgs tree
      nixos-option # for searching options
      nload # network load monitor
      nufmt # A formatter for nushell
      nushell # Modern shell written in Rust
      nushellPlugins.gstat # A nushell plugin to show git status
      nushellPlugins.net # Network plugins for nushell
      nushellPlugins.query # Nushell plugin to query JSON, XML, and various web data
      # nushellPlugins.skim # A nushell plugin that integrates the skim fuzzy finder # it couldn't find it on 5/7/2025
      # nushellPlugins.units # A nushell plugin to convert units # it couldn't find it on 5/7/2025
      nmon # for monitoring system performance
      nordic # for nordic theme
      obsidian # a note-taking app based on plain markdown files
      oil # A Posix shell that aims to replace Bash. We'll see...
      p7zip # 7zip
      pandoc # Universal markup converter
      par2cmdline-turbo # par2cmdline × ParPar: speed focused par2cmdline fork
      pciutils # for lspci
      peaclock # a nice timer TUI
      perf-tools # for profiling
      pkg-config # for compiling stuff
      polybar # status bar
      protontricks # automates installing winetricks packages for proton
      psmisc # provides killall, fuser, prtstat, pslog, pstree, peekfd
      pv # pipe viewer
      ranger # file manager
      rdfind # finds dupes, optionally acts on them
      rescuetime # usage tracking; currently configured to run for all users, above
      ripgrep # rg, the best grep
      rund # Compiler-wrapper that runs and caches D-lang programs
      rustc # rust compiler
      shellcheck # A static analysis tool for shell scripts
      smartmontools
      sshfs # for mounting remote filesystems
      nvtopPackages.full # for GPU info # downgraded to stable on 6/23/2023 due to build failure on unstable
      sysz # An fzf-based terminal UI for systemctl
      timer # a `sleep` with progress TUI
      tmux # Terminal multiplexer
      tokei # fast LOC counter
      tree # view directory structure
      uair # a minimal pomodoro timer GUI/TUI
      uget # a download manager GUI
      unrar # a rar extractor
      vim # it's no emacs
      vulkan-tools # for profiling
      wezterm # nerdy but very nice terminal
      wget # wget is better than curl because it will resume with exponential backoff
      whitesur-gtk-theme
      whitesur-icon-theme
      winetricks # winetricks is a helper script to download and install various redistributable runtime libraries needed to run some programs in Wine.
      wmctrl # for controlling window managers
      wsysmon # like Windows Task Manager but for Linux
      xclip # clipboard interaction
      xinetd # provides tftp etc. (originally installed to play with symbolics opengenera)
      xorg.xbacklight # for controlling screen brightness
      xxHash # Extremely fast hash algorithm
      xz # Library and command-line tools for LZMA2 compression
      zathura # a better document viewer (pdf's etc)
      zenith-nvidia # zoom-able charts (there is also a non-nvidia version)
      zfs # the best filesystem on the planet
      zoxide # A smarter cd command inspired by z
      zsh # A user-friendly and interactive shell which is yet not sufficiently better than Bash to merit its use
      zstd # Zstandard real-time compression algorithm
      (pkgs.callPackage ./yuescript.nix { })
    ] ++ lib.attrValues luajitUserPackages;

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
      LUA_PATH = luaPath;
      LUA_CPATH = luaCPath;
      GMP_PATH = if pkgs.stdenv.isDarwin 
           then "${pkgs.gmp}/lib/libgmp.dylib" 
           else "${pkgs.gmp}/lib/libgmp.so";
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

  # Disable default lid-closed behavior
  services.logind.extraConfig = ''
    HandleLidSwitch=ignore
    HandleLidSwitchDocked=ignore
  '';

  # Only valid for Home Manager
  # dconf.settings = {
  #   "org/gnome/settings-daemon/plugins/power" = {
  #     lid-close-ac-action = "nothing";
  #     lid-close-battery-action = "suspend";  # Optional — only suspend when on battery
  #   };
  # };


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
