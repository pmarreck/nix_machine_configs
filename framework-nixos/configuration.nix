# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, inputs, system, ... }:
# `inputs` + `system` are injected via flake specialArgs (see /etc/nixos/flake.nix).
# This replaces the old <nixos-unstable>/<nixos-stable>/<nixos-hardware> channel
# lookups while keeping the host-specific package scopes in this module.
let
  # FYI: My system got switched to unstable,
  # but I left in the unstable scoping for my original "unstable" packages
  # (I don't believe this should cause any problems)
  # and added a "stable" scope for any packages that break in unstable
  # so I can just downgrade them to stable on a case by case basis
  scopeConfig = {
    allowUnfree = true;
  };
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
  stable = import inputs.nixpkgs-2605 { inherit system; config = scopeConfig; };
  # my custom proprietary fonts
  key-rebel-moon = pkgs.callPackage ./key-rebel-moon.nix { };
  tech-alive = pkgs.callPackage ./tech-alive.nix { };
  # which particular version of elixir and erlang I want globally
  erlang = unstable.erlang; # I like to live dangerously. For fallback, use stable of: # erlangR25;
  elixir = pkgs.beam.packages.erlangR28.elixir_1_18;
  # libretro = stable.libretro;
  comma = pkgs.comma;
  opencode = pkgs.callPackage ./opencode.nix { };
  cfunge = pkgs.callPackage ./cfunge.nix { };
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
      ./low-memory-notify.nix
      inputs.nixos-hardware.nixosModules.framework-16-7040-amd
    ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "electron-25.9.0"
    "mailspring-1.12.0" # CVE-2023-4863
  ];

  # for ollama acceleration
  nixpkgs.config.rocmSupport = true;

  nix.settings = {
    download-buffer-size = 1048576000; # 1GB
    "warn-dirty" = false;
    trusted-users = [ "root" "pmarreck" ];
  };

  # Avoid building fragile package HTML docs as part of the system profile.
  documentation.doc.enable = false;

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

    # The Azurite-backed Arrow filesystem test flakes locally. Keep Azure support
    # and the remaining install checks while nixpkgs carries the upstream test.
    (final: prev: {
      arrow-cpp = prev.arrow-cpp.overrideAttrs (old: {
        installCheckPhase = prev.lib.replaceStrings
          [ "arrow-orc-adapter-test" ]
          [ "arrow-orc-adapter-test|arrow-azurefs-test" ]
          old.installCheckPhase;
      });
    })

    # ---------------------------------------------------------------------
    # JPEG XL (.jxl) support for GTK / GNOME apps via gdk-pixbuf.
    #
    # Why this exists (added 2026-05-04, on nixos-25.11 / GNOME 49.4):
    #   GNOME's image stack is mid-migration from gdk-pixbuf to the new
    #   `glycin` library. GNOME 50 (2026-03-18, 50.1 in April) made glycin
    #   the default for Nautilus thumbnails with greatly improved JXL
    #   performance, but nixos-25.11 stable is locked to GNOME 49, which
    #   still goes through gdk-pixbuf for thumbnails. And even on GNOME 50,
    #   plenty of GTK apps (the wallpaper chooser in gnome-control-center,
    #   GTK file pickers, third-party viewers, eog) still load via
    #   gdk-pixbuf and need the libjxl loader compiled in. Adding
    #   `pkgs.libjxl` to systemPackages alone only registers the
    #   freedesktop thumbnailer, not in-app image loads.
    #
    # When to remove this overlay:
    #   1. After upgrading to nixos-26.05 (expected late May 2026) which
    #      should ship GNOME 50.x with glycin handling Nautilus thumbnails
    #      natively — at that point the overlay is no longer needed for
    #      *thumbnails*, but is still useful for non-glycin GTK apps.
    #   2. After GNOME 51 (expected ~2026-09) widens glycin adoption to
    #      gnome-control-center / gnome-backgrounds / GTK pickers, and
    #      nixos-26.11 (~Nov 2026) ships it on the stable channel.
    #
    # Re-evaluate around Dec 2026 / Jan 2027: if every GTK app on the
    # system reads .jxl without this override, delete the block below.
    # Quick check: rename a .jxl, set as wallpaper via Settings, open in
    # Loupe / eog, browse a folder of .jxl in Nautilus.
    # ---------------------------------------------------------------------
    # DISABLED 2026-06-07: this gdk-pixbuf jxl override changes gdk-pixbuf's hash,
    # which cascades a full from-source rebuild of the GTK/Qt/electron tree on every
    # nixpkgs bump (gtk+3 -> firefox/webkit/libreoffice/gnome; qtbase->gtk3->KDE).
    # Traded for cache hits; big-desktops images rolled back to pre-jxl (fab0aa6).
    # Re-enable at nixos-26.11 / GNOME 51 when glycin handles gnome-backgrounds natively.
    /*
    (final: prev:
      let
        # Fresh nixpkgs import without any overlays — used solely to
        # reference libjxl's prebuilt loader .so without re-entering this
        # overlay's fixpoint (libjxl → libavif → ... → gdk-pixbuf cycle).
        cleanPkgs = import <nixpkgs> {
          localSystem = prev.stdenv.hostPlatform.system;
          overlays = [ ];
          config = { };
        };
      in {
        gdk-pixbuf = prev.gdk-pixbuf.overrideAttrs (old: {
          postFixup = (old.postFixup or "") + ''
            cp ${cleanPkgs.libjxl}/lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader-jxl.so \
              $out/lib/gdk-pixbuf-2.0/2.10.0/loaders/
            GDK_PIXBUF_MODULEDIR=$out/lib/gdk-pixbuf-2.0/2.10.0/loaders \
              $dev/bin/gdk-pixbuf-query-loaders --update-cache
          '';
        });
      })
    */

    # Skip flaky test suites in Python packages that assert on wall-clock
    # timing — they pass on idle dev laptops, fail under build-host load,
    # and have nothing to do with whether the package actually works.
    #   - liquidctl 1.15.0: tests/test_keyval.py timing race (multiprocess)
    #   - ipython 9.5.0: test_stream_performance asserts duration < 10s
    # Disable tests outright (doCheck = false) for these — surgical scalpel
    # rather than the disabledTests scalpel, since these suites have shown
    # they don't catch anything worth blocking a system rebuild on.
    # Re-enable per package whenever upstream replaces the timing assertions
    # with deterministic checks.
    (final: prev:
      let
        # Disable doCheck on packages whose test suite flakes on busy build
        # hosts. Override at the *interpreter* level (python3X.override
        # with packageOverrides) — overriding pythonXPackages directly only
        # patches the alias and is bypassed by anything resolving via
        # python3X.pkgs.<pkg> or python3X.withPackages.
        flakyPyOverrides = pyfinal: pyprev: {
          # liquidctl 1.15.0: tests/test_keyval.py::test_fs_backend_stores_
          # honor_load_store_locking races on time.sleep-based sync.
          liquidctl = pyprev.liquidctl.overridePythonAttrs (_: { doCheck = false; });
          # ipython 9.5.0: test_stream_performance asserts wall-clock
          # duration < 10s for printing 250k lines (regression test for an
          # O(n²) → O(n) fix). Fails on busy hosts; replacement upstream
          # at https://github.com/ipython/ipython/pull/15201.
          ipython = pyprev.ipython.overridePythonAttrs (_: { doCheck = false; });
          # httpcore 1.0.9: test_connection_pool_timeout_during_request[trio]
          # is a flaky async-cancellation timing test — asserts the pool is
          # cleaned up immediately after cancel, but under load the trio
          # scheduler hasn't propagated cleanup when the assert fires.
          httpcore = pyprev.httpcore.overridePythonAttrs (_: { doCheck = false; });
          # aiohttp 3.13.3: test_regex_performance and
          # test_cookie_pattern_performance both assert wall-clock
          # `duration < 0.01` (10ms!) — guaranteed to flake on any
          # non-pristine build host.
          aiohttp = pyprev.aiohttp.overridePythonAttrs (_: { doCheck = false; });
          # curl-cffi 0.14.x: tests/unittest hangs indefinitely under
          # pytest-xdist (observed: 18 workers idle for 24h, ~0% CPU,
          # blocked on async I/O — likely a websocket/impersonate test
          # whose deselect list didn't fully cover the offender).
          curl-cffi = pyprev.curl-cffi.overridePythonAttrs (_: { doCheck = false; });
        };
      in {
        python311 = prev.python311.override { packageOverrides = flakyPyOverrides; };
        python312 = prev.python312.override { packageOverrides = flakyPyOverrides; };
        python313 = prev.python313.override { packageOverrides = flakyPyOverrides; };
      })

    # power-profiles-daemon 0.30: integration test Tests.test_vanishing_hold
    # (tests/integration_test.py) is a timing-sensitive dbus test — it sets a
    # profile "hold", then asserts exactly one hold exists, and gets zero
    # (AssertionError: 0 != 1). On a busy build host the hold hasn't propagated
    # when the assert fires; observed here running 3610s (~1h) and failing while
    # skia/WebKit/gtk4/Qt were all compiling in parallel.
    #
    # NB: doCheck=false ALONE breaks this package — nixpkgs hardcodes
    # `-Dtests=true` in mesonFlags but only supplies umockdev via
    # nativeCheckInputs *when doCheck is true*, so doCheck=false makes meson
    # configure fail: "GObject Introspection module 'UMockdev' ... not found".
    # So we also force `-Dtests=false` (drop the hardcoded true), which removes
    # the umockdev requirement and skips building/running the suite entirely.
    # Remove when upstream makes test_vanishing_hold deterministic.
    (final: prev: {
      power-profiles-daemon = prev.power-profiles-daemon.overrideAttrs (old: {
        mesonFlags =
          (builtins.filter
            (f: !(builtins.isString f && prev.lib.hasPrefix "-Dtests=" f))
            (old.mesonFlags or []))
          ++ [ "-Dtests=false" ];
        doCheck = false;
      });
    })

    # ibus 1.5.33 has a parallel-install race in bindings/pygobject:
    # `install IBus.py` fires twice in parallel and one invocation fails
    # with "File exists". Forcing serial install avoids the race without
    # affecting build correctness. Remove when nixpkgs picks up an ibus
    # release that fixes the upstream Makefile dependency.
    (final: prev: {
      ibus = prev.ibus.overrideAttrs (old: {
        enableParallelInstalling = false;
      });
    })

    # gjs 1.86.0: Scripts/CommandLine subtest "Throws error if filename is
    # not UTF8" is locale/filesystem-sensitive — touches a file with a raw
    # 0xFF byte in the name and aborts on locales that reject the byte.
    # Passes in the upstream binary cache (CI uses a tolerant setup); we
    # hit it only because the gdk-pixbuf override forces gjs to rebuild
    # from source. Disable the test phase, AND pass -Dskip_gtk_tests=true
    # because nixpkgs gates gtk3/gtk4 on doCheck via nativeCheckInputs,
    # but gjs's meson.build hard-errors at *configure time* without GTK
    # unless that flag is set.
    # DISABLED 2026-06-07: only needed because the gdk-pixbuf override (now disabled
    # above) forced gjs to rebuild from source. With that gone, gjs substitutes from
    # cache — and keeping this override would itself change gjs's hash and force the
    # very rebuild we're trying to avoid. Re-enable alongside the gdk-pixbuf override.
    /*
    (final: prev: {
      gjs = prev.gjs.overrideAttrs (old: {
        doCheck = false;
        doInstallCheck = false;
        mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dskip_gtk_tests=true" ];
      });
    })
    */
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Preserve the pre-26.11 root-pool import behavior explicitly. This is a
  # single-host root pool; set false if the pool is ever shared across machines.
  boot.zfs.forceImportRoot = true;

  # Provide compressed swap in RAM (minimal SSD wear, decent burst capacity).
  zramSwap = {
    enable = true;
    memoryPercent = 50; # ~32 GiB logical swap from 64 GiB RAM
    priority = 100;
  };

  boot.kernel.sysctl = {
    "kernel.sysrq" = 1;
  };

  # Intentionally empty: declaring the zvol here makes NixOS stage-1 initrd
  # block waiting for /dev/zvol/rpool/swap. We activate it post-boot via the
  # systemd unit below, after zfs-import has settled.
  swapDevices = [ ];

  systemd.services.zvol-swap = {
    description = "Activate ZFS zvol swap after pool import";
    after = [ "zfs-import.target" "systemd-udev-settle.service" ];
    wants = [ "zfs-import.target" ];
    requires = [ "zfs-import.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.util-linux}/bin/swapon -p 50 /dev/zvol/rpool/swap";
      ExecStop = "${pkgs.util-linux}/bin/swapoff /dev/zvol/rpool/swap";
    };
  };

  # boot.resumeDevice removed: was forcing initrd to wait ~58s for the zvol
  # device node to appear just to check for a hibernation resume image.
  # Hibernation will no longer resume; zram + zvol swap remain for paging.
  # boot.resumeDevice = "/dev/zvol/rpool/swap";

  # AMD support
  boot.kernelModules = [ "amdgpu" "radeon" ];
  boot.kernelParams = [ "radeon.si_support=0" "amdgpu.si_support=1" "radeon.cik_support=0" "amdgpu.cik_support=1" ];
  # boot.extraModulePackages = with config.boot.kernelPackages; [ linuxPackages.amdgpu ];
  # boot.extraModulePackages = [ pkgs.linuxKernel.packages.linux_6_6.amdgpu-pro ];
  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # for 32-bit apps (Steam, etc.)
  };

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
    videoDrivers = [ "amdgpu" ];
  };

  # avahi bonjour service
  services.avahi = {
    enable = true;
    nssmdns4 = true;
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
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # framework laptop
  services.fwupd.enable = true;

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound.
  # sound.enable = true; # disabled in 25.05
  services.pulseaudio.enable = false;
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

  # tailscale
  services.tailscale.enable = true;
  services.tailscale.openFirewall = true;  # opens 41641/udp etc.

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.pmarreck = {
    isNormalUser = true;
    description = "Peter Marreck";
    extraGroups = [ "networkmanager" "wheel" "tty" "input" "openrazer" "audio" "plugdev" "disk" ];
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
      unstable.beyond-all-reason # Free Real Time Strategy Game with a grand scale and full physical simulation in a sci-fi setting
      bfs # better, breadth-first search
      unstable.binaryen # Compiler infrastructure and toolchain library for WebAssembly, in C++
      blesh # Bash line editor with syntax highlighting
      bluemail # email client # doesn't currently work...
      boinc # distributed computing
      boohu # Break Out Of Hareka's Underground (Boohu) is a turn-based coffee-break roguelike game with a heavy focus on tactical positioning mechanisms. https://github.com/anaseto/boohu
      bottom # Like top but bottomer
      brogue-ce # Community-lead fork of the minimalist roguelike game Brogue, with many improvements
      browsh # graphical web browser in the terminal
      bun # Fast JavaScript runtime and package manager
      unstable.capstone # Advanced disassembly library
      unstable.circumflex # Hacker News TUI (command: "clx")
      # claude-code and codex removed (installed via pipx/pnpm/volta instead)
      clinfo
      colordiff # A tool to colorize diff output
      crawl # roguelike
      crawlTiles # roguelike
      crystal # Compiled language with Ruby-like syntax and type inference
      csvkit # Various tools for working with CSV files such as csvlook, csvcut, csvsort, csvgrep, csvjoin, csvstat, csvsql, etc.
      curlpp # for curl bindings in C++
      darktable # photo editor # forced stable on 1/24/2023 due to build failure on unstable
      delta #syntax highlighter for git
      unstable.deno # Secure runtime for JavaScript and TypeScript
      dirb # Web content scanner for finding hidden files/directories
      discord # chat app for gamers
      unstable.dosbox-staging # Modernized DOS emulator; DOSBox fork
      drawing # drawing program
      dunst # notification daemon for x11; wayland has "mako"; discord may crash without one of these
      egoboo # 3D dungeon crawling adventure
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
      fzf # fuzzy finder
      fzy # fuzzy finder that's faster/better than fzf
      galculator # calculator GUI
      # gamehub # marked broken on nixos-25.11
      gawkInteractive # GNU awk with readline support and better error messages
      gcc # compiler for C
      unstable.gemini-cli # Google's AI agent that brings the power of Gemini directly into your terminal
      ghidra # Software reverse engineering (SRE) suite of tools from the NSA
      ghostscript # Ghostscript is an interpreter for the PostScript language and PDF files
      glow # markdown viewer TUI
      # Expose only glxinfo from mesa-demos (the package itself ships ~30
      # binaries, most of which are demos that don't run independently
      # and just pollute PATH). nixpkgs doesn't have a separate mesa-utils
      # like Debian, so we filter at the systemPackages level.
      (pkgs.runCommand "glxinfo-only" { } ''
        mkdir -p $out/bin
        ln -s ${pkgs.mesa-demos}/bin/glxinfo $out/bin/glxinfo
      '')
      gmp # GNU Multiple Precision Arithmetic Library
      gravit # gravity simulator
      gthumb # image viewer
      harmonist # roguelike
      hyperfine # command-line benchmarking tool
      hyperrogue # roguelike
      hyperscan # High-performance multiple regex matching library
      inkscape-with-extensions # Vector graphics editor with extensions
      jazz2 # open source reimplementation of classic Jazz Jackrabbit 2 game
      jetbrains.datagrip # gui for postgresql/mariadb/mysql/sqlite
      jq # json query
      krita # drawing program
      less # GNU terminal based program for paging text files or output
      libheif # ISO/IEC 23008-12:2017 HEIF file format decoder and encoder
      libjxl # JPEG XL image format reference implementation
      libwebp # Library and tools for the WebP image format
      lightspark # Flash (ActionScript 3) runner
      links2 # Small text-mode browser with some graphics support
      mailspring # nice open-source email client
      unstable.gum # looks like a super cool TUI tool for shell scripts: https://github.com/charmbracelet/gum
      unstable.signal-desktop # signal desktop client
      # wasistlos was removed from nixpkgs after upstream archived it.
      # unstable.karere # whatsapp desktop client replacement; enable if wanted
      meritous # Action-adventure dungeon crawl game
      moor # a better "less"
      mono # for C#/.NET stuff
      # nasc # "do maths like a normal person", it says. I'm intrigued. # Neat, but disabled due to build failures for now :(
      nethack # roguelike
      newtonwars # missile game with gravity as a core element
      nim # Nim programming language
      nixd # nix language server
      nmap # Network exploration tool and security scanner
      nms # No More Secrets, a recreation of the live decryption effect from the famous hacker movie "Sneakers"
      nnn # Terminal file manager
      # nodejs_20 # javascript runtime # moved to managing via Volta
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
      pnpm # efficient javascript package manager
      pkgs."poppler-utils" # PDF tools
      presenterm # A markdown-based terminal slideshow tool
      procps # Utilities that give information about processes
      # proton-caller # removed in nixos-25.11 (unmaintained)
      python312Packages.pygments # Syntax highlighting library
      conda # python package manager (ew. but need it for LLM's)
      python311Packages.pandas # for data analysis
      python311Packages.pillow # for image processing
      python311Packages.pip # for pip
      python311Packages.pygments # syntax highlighting for 565 languages in terminal
      python311Packages.python # python interpreter
      python311Packages.tkinter # for tkinter
      # python311Packages.torch-bin # disabled on 26.x: PyTorch expects newer CUDA bindings than nixpkgs provides
      # python311Packages.torchaudio-bin
      # python311Packages.torchvision-bin
      python311Packages.virtualenv # for virtualenv
      qalculate-gtk # very cool calculator
      qFlipper # for Flipper Zero
      qpdf # C++ library and set of programs that inspect and manipulate the structure of PDF files
      radare2 # reverse engineering framework/disassembler
      rclone # rsync for cloud storage
      rclone-browser # GUI for rclone
      reader # Lightweight tool offering better readability of web pages on the CLI
      recoll # full-text search tool
      rhythmbox # audio player
      ruffle # Flash (soon ActionScript 3) runner
      sampler # TUI for shell commands execution, visualization and alerting
      sc-im # Spreadsheet Calculator Improved - terminal spreadsheet program
      scorched3d # played the original version a lot in the military
      sd # Intuitive find & replace CLI tool
      # sequeler # disabled on nixos-25.11 (libgda build fails: AM_ICONV)
      shattered-pixel-dungeon # Traditional roguelike game with pixel-art graphics and simple interface. Variants follow:
        shorter-pixel-dungeon # A shorter fork of the Shattered Pixel Dungeon roguelike
        summoning-pixel-dungeon # A fork of the Shattered Pixel Dungeon roguelike with added summoning mechanics
        tower-pixel-dungeon # Turn-based tower defense game based on Shattered Pixel Dungeon
        experienced-pixel-dungeon # A fork of the Shattered Pixel Dungeon roguelike without limits on experience and items
        rkpd2 # Fork of popular roguelike game Shattered Pixel Dungeon that drastically buffs heroes and thus makes the game significantly easier
        rat-king-adventure # An expansive fork of RKPD2, itself a fork of the Shattered Pixel Dungeon roguelike
      shortwave # internet radio
      shotwell # photo organizer like iPhoto
      sil # Rogue-like game set in the First Age of Middle-earth
      slack # the chat app du jour
      sourceHighlight # Source code renderer with syntax highlighting
      speedread # speed reading
      speedtest-cli # Internet speed test from the command line
      unstable.cudaPackages.cudatoolkit # for tensorflow
      # unstable.curl-impersonate # Command-line tool to impersonate a browser
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
      silver-searcher-ng # Maintained fork of silver-searcher with PCRE2 support
      stable.spotify # forced stable on 2/16/2023 due to build failure on unstable
      stable.spotifyd # spotify streamer daemon
      starship # cool prompt
      taoup # The Tao of Unix Programming
      stable.telegram-desktop # chat app
      unstable.television # Blazingly fast general purpose fuzzy finder TUI
      tesseract # OCR
      the-powder-toy # sandbox game
      ticker # stock market watcher, to replace the "markets" GUI
      tickrs # Another TUI stock market watcher
      # tome2 # A dungeon crawler similar to Angband, based on the works of Tolkien # disabled due to build failures
      torcs # racing game
      # transmission-gtk # torrent client
      transmission_4-gtk # torrent client
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
      unstable.orbiton # Simple text editor/IDE intentionally limited to VT100; https://github.com/xyproto/o
      unstable.ollama # playing with LLM's
      unstable.vscode # nice gui editor
      unstable.zed-editor # code editor
      unvanquished # FPS
      visidata # Terminal TUI spreadsheet multitool for discovering and arranging data
      vsce # Visual Studio Code extensions manager/tooling
      vlc # video player
      unstable.wabt # WebAssembly Binary Toolkit
      unstable.wasm-tools # Low level tooling for WebAssembly in Rust (very useful)
      unstable.wasmedge # Lightweight, high-performance, and extensible WebAssembly runtime for cloud native, edge, and decentralized applications
      unstable.wasmtime.out # wasm runtime
      unstable.wazero # Zero dependency WebAssembly runtime written in Go, currently the fastest wasm runner
      wdiff # A front end to diff for comparing files on a word per word basis
      unstable.devin-desktop # windsurf was rebranded/replaced
      unstable.wiper # TUI tool that pinpoints large folders, scans directories and shows how your space is used
      xaos # smooth fractal explorer
      xdotool # for automating x11. Fake keyboard/mouse input, window management, and more
      xlife # cellular automata
      xscreensaver # note that this seems to require setup in home manager
      unstable.zellij # "Terminal workspace with batteries included" (basically a nicer tmux with a worse name. notably, uses webasm plugins)
      unstable.zmate # instant terminal sharing, using Zellij
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

      # IXNAY USER PACKAGES (pmarreck) START - DO NOT REMOVE
      unstable.antigravity # Agentic development platform, evolving the IDE into the agent-first era
      cfunge # Fast Befunge interpreter
      unstable.gh # GitHub CLI tool
      opencode # AI coding agent built for the terminal
      # IXNAY USER PACKAGES (pmarreck) END - DO NOT REMOVE
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
      startAgent = false; # GNOME enables gcr-ssh-agent; avoid conflicting SSH agents
      extraConfig = ''
        Host *
          AddKeysToAgent yes
          IdentityFile ~/.ssh/id_ed25519
      '';
    };
    gamemode.enable = true; # for steam
    dconf.enable = true;
    nix-ld.enable = true;
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
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      powerline-fonts
      source-code-pro
      tech-alive # another favorite sans serif font with obfuscated name
      # terminus-nerdfont
    ] ++ builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);
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

    ]);

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    systemPackages = with pkgs; [
      (wineWow64Packages.unstableFull.override { wineRelease = "staging"; mingwSupport = true; })
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
      cheese # gnome webcam tool
      chez # Chez Scheme (useful for idris)
      chromium # like chrome but without the google
      # clipgrab # disabled on nixos-25.11 (qtwebengine-5.15.x is marked insecure)
      comma # for trying out software, see "let" section above
      conky # system monitor
      cool-retro-term # a retro terminal emulator
      coreutils-prefixed # most gnu utils prefixed with "g" to disambiguate them in cross platform scripts that make buggy assumptions
      cosmocc # Cosmopolitan (Actually Portable Executable) C/C++ toolchain; use via CC=cosmocc, CXX=cosmoc++
      cowsay # a classic
      curl # curl is better than wget because it supports more protocols
      dcfldd # dd with progress bar and inline hash verification
      dconf2nix # for converting dconf settings to nix
      # direnv # for loading environment variables from .env and .envrc files # Now added below
      # dmd # fails to build with GCC 15 headers; ldc below remains available for D.
      # dstat # example use: dstat -cdnpmgs --top-bio --top-cpu --top-mem # removed due to unmaintained
      dool # replacement for dstat
      duc # disk usage visualization, highly configurable
      duf # really nice disk usage TUI
      efibootmgr # for managing EFI boot entries
      emacs # it's no vim
      epiphany # gnome web browser
      et # A minimal (egg) timer TUI based on libnotify
      evince # gnome's document viewer (pdfs etc)
      eza # A modern replacement for ls (fork of exa)
      fd # a better "find"
      file # file type identification
      # frawk # An efficient AWK-like language # fails to build as of december 2025
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
      gnome-characters # gnome character map
      gnome-music # music player
      gnome-solanum # timer GUI
      gnome-terminal # terminal emulator
      dconf-editor # for editing gnome settings
      gnome-tweaks # may give warning about being outdated? only shows it once, though?
      sushi # gnome file previewer (just hit spacebar in Gnome Files)
      zenity # gnome zenity, a GUI dialog box tool
      gnomeExtensions.appindicator # for system tray icons
      gnomeExtensions.dash-to-dock # for moving the dock to the bottom
      gnomeExtensions.freon # for monitoring CPU and GPU temps
      gnomeExtensions.lock-keys # for showing caps lock etc
      # gnomeExtensions.miniview # missing in nixos-25.11
      gnomeExtensions.night-theme-switcher # for automatically switching between light and dark themes
      gnomeExtensions.paperwm # Tiling window manager with a twist!
      gnomeExtensions.pop-shell # for tiling windows
      gnomeExtensions.rclone-manager # adds an indicator to the top panel so you can manage the rclone profiles configured in your system
      gnomeExtensions.vitals # for monitoring CPU and GPU temps
      totem # gnome video player
      tali # gnome poker game
      iagno # gnome go game
      hitori # gnome sudoku game
      atomix # gnome puzzle game
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
      firefox-beta # firefox nightly overlay fetches live Mozilla metadata, which is not flake-pure
      ldc # d-lang LLVM compiler
      libreoffice-fresh # needed for gnome sushi to preview Office files, otherwise *big hang*. No idea if I picked the right LibreOffice as there's like a dozen variants and NO docs about this.
      lsof # for listing open files and ports
      luajit # High-performance JIT compiler for Lua 5.1
      lz4 # Extremely fast compression algorithm
      unstable.yt-dlp # for downloading videos from youtube and other sites
      mcfly # fantastic replacement for control-R history search
      meld # visual diff and merge tool
      mkpasswd # for generating passwords
      monitor # yet another sexy system monitor
      mpv # media player
      murex # awesome looking shell, see murex.rocks
      ncdu # "ncurses du (disk usage)"
      fastfetch # system info (neofetch was removed from nixpkgs)
      nethogs # network bandwidth monitor
      nitrogen # wallpaper/desktop image manager
      nix-bash-completions # bash completions for nix
      # nix-direnv # direnv integration for nix # Now added below
      nix-index # also provides nix-locate
      nix-tree # show nixpkgs tree
      nixos-option # for searching options
      nload # network load monitor
      nufmt # A formatter for nushell
      nushell # Modern shell written in Rust
      nushellPlugins.gstat # A nushell plugin to show git status
      # nushellPlugins.net # broken on nixos-25.11 (nu_plugin_net marked broken)
      nushellPlugins.query # Nushell plugin to query JSON, XML, and various web data
      # nushellPlugins.skim # A nushell plugin that integrates the skim fuzzy finder # it couldn't find it on 5/7/2025
      # nushellPlugins.units # A nushell plugin to convert units # it couldn't find it on 5/7/2025
      nmon # for monitoring system performance
      nordic # for nordic theme
      obsidian # a note-taking app based on plain markdown files
      # oil # A Posix shell that aims to replace Bash. We'll see...
      oils-for-unix # A Posix shell that aims to replace Bash. We'll see...
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
      rage # Simple, secure and modern encryption tool with small explicit keys, no config options, and UNIX-style composability
      ranger # file manager
      rdfind # finds dupes, optionally acts on them
      reptyr # Reattach/reparent a running program to a new terminal (only works on Linux!)
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
      unzip # how was this not installed by default?
      vim # it's no emacs
      vulkan-tools # for profiling
      watchman # Watches files and takes action when they change
      wezterm # nerdy but very nice terminal
      wget # wget is better than curl because it will resume with exponential backoff
      whitesur-gtk-theme
      whitesur-icon-theme
      winetricks # winetricks is a helper script to download and install various redistributable runtime libraries needed to run some programs in Wine.
      wmctrl # for controlling window managers
      wootility # Customization and management software for Wooting keyboards
      wooting-udev-rules # udev rules that give NixOS permission to communicate with Wooting keyboards
      wsysmon # like Windows Task Manager but for Linux
      xclip # clipboard interaction
      xinetd # provides tftp etc. (originally installed to play with symbolics opengenera)
      xbacklight # for controlling screen brightness
      xxhash # Extremely fast hash algorithm
      xz # Library and command-line tools for LZMA2 compression
      zathura # a better document viewer (pdf's etc)
      zenith-nvidia # zoom-able charts (there is also a non-nvidia version)
      zfs # the best filesystem on the planet
      zoxide # A smarter cd command inspired by z
      sysstat # not sure if needed, provides sa1 and sa2 commands meant to be run via crond?
      zsh # A user-friendly and interactive shell which is yet not sufficiently better than Bash to merit its use
      zstd # Zstandard real-time compression algorithm
      libjxl # JPEG XL CLI tools + freedesktop thumbnailer (.jxl); see overlay note above
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

  programs.direnv.enable = true;

  # Enable mosh (mobile shell) - a remote terminal that supports roaming and intermittent connectivity
  programs.mosh = {
    enable = true;
    openFirewall = true;
  };

  programs.gnupg.agent = {
    enable = true;
    # enableSSHSupport = true;
    pinentryPackage = pkgs.pinentry-gnome3;
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Disable default lid-closed behavior
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # ZFS housekeeping
  services.zfs = {
    autoScrub = {
      enable = true;
      pools = [ "rpool" ];
      interval = "monthly";   # systemd OnCalendar string
    };
    # Drop `zed.enable`. If you want tweaks, use zed.settings (optional):
    # zed.settings = { ZED_NOTIFY_VERBOSE = "1"; };
  };

  # Only valid for Home Manager
  # dconf.settings = {
  #   "org/gnome/settings-daemon/plugins/power" = {
  #     lid-close-ac-action = "nothing";
  #     lid-close-battery-action = "suspend";  # Optional — only suspend when on battery
  #   };
  # };


  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 8200 ]; # DLNA (minidlna) for cast-to-tv
  networking.firewall.allowedUDPPorts = [ 1900 ]; # SSDP/UPnP discovery for DLNA
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Unsupported under flakes: a flake is a source tree, not one configuration file.
  # The config is source-controlled here, which supersedes the old copy hook.
  system.copySystemConfiguration = false;

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
