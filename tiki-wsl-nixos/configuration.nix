{ pkgs, tmog, hunkPackage, ... }:

let
  # Existing pinned/obfuscated package for the licensed Berkeley Mono files.
  key-rebel-moon = pkgs.callPackage ../framework-nixos/key-rebel-moon.nix { };
  darwinPackageParity = import ./darwin-package-parity.nix { inherit pkgs; };
  cosmocc = pkgs.callPackage ../cosmocc-bin.nix { }; # promoted to repo root 2026-08-12, shared by all hosts
in
{
  networking.hostName = "tiki-wsl";

  # The NixOS-WSL module is supplied by this repository's flake.
  wsl.enable = true;
  wsl.defaultUser = "nixos";
  # Retain ordinary Windows PE execution. The cosmocc package handles its own
  # bundled APE tools without changing this deliberately broad WSL handler.
  wsl.interop.register = true;
  wsl.startMenuLaunchers = true;
  wsl.useWindowsDriver = true;

  # GUI application exposed through WSLg without making it system-wide.
  users.users.nixos.packages = [
    pkgs.fastfetch
    hunkPackage
    tmog
  ];

  # WSL instances are routinely stopped rather than shut down conventionally.
  boot.tmp.cleanOnBoot = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];

    # This account is the dedicated remote-builder identity for this guest.
    # Trusted Nix users are effectively root-capable through the daemon.
    trusted-users = [ "root" "nixos" ];
  };

  # Useful for editor-managed language servers and other dynamically linked
  # development tools that assume a conventional Linux loader path.
  programs.nix-ld.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # Install the mosh client without opening inbound ports on this WSL guest.
  programs.mosh.enable = true;

  # Symmetric and private-key operations must be able to request a passphrase
  # in the Windows-hosted WezTerm session. The module writes the pinentry's
  # absolute store path into /etc/gnupg/gpg-agent.conf.
  programs.gnupg.agent = {
    enable = true;
    pinentryPackage = pkgs.pinentry-curses;
  };

  # Shared shell startup prefers $AWK when already defined. frawk 0.4.8's
  # Cranelift backend panics on the programs used by distro/distro_version on
  # this host, so retain frawk as an explicit tool but use GNU Awk by default.
  environment.variables.AWK = "${pkgs.gawkInteractive}/bin/gawk";

  # Give the WSL guest its own tailnet identity, distinct from the Windows
  # host. Authenticate it once after activation with `sudo tailscale up`.
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  # SSH is reachable only through Tailscale. Authentication is key-only and
  # root logins are forbidden.
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      AllowUsers = [ "nixos" ];
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

  # Public keys currently published by the pmarreck GitHub account. They are
  # pinned here so access does not depend on GitHub being available at login.
  users.users.nixos.openssh.authorizedKeys.keys = [
    # Local Windows host identity for pmarreck@tiki.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPz32aqFkNSfkSfsLQA7sLrEcSDmL12PfbpZw2WLgxRp pmarreck@tiki"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDV83uhVebrJDGUxBQ2rkndnNg/PtN7/pPTP1lThBPU/"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF6hPXHhQAKTqfOQzDA2GiX10yhd4v5jGIEmHZC9voSo"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINqONS5Ocpxl46qwyopyM3PaW5g1B2BIYEsmUdCUn7Tg"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN8CaI01OX7799ZuTy7o0OO/8NkG7xgUuyVl4eqA0P0U"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN7r2PP9o5XpYCzvvryBoUqbjd7lCGuM9to8/qBKmsJ6"
  ];

  # Linux GUI applications use WSLg and the Windows host's GPU driver.
  hardware.graphics.enable = true;
  fonts.packages = with pkgs; [
    atkinson-hyperlegible
    fira-code
    key-rebel-moon
    nerd-fonts.jetbrains-mono
    nerd-fonts.symbols-only
  ];

  # Mirror the active cross-platform package inventory from the nix-darwin
  # machine, then add tools specific to this WSL development guest.
  # Windows-native WezTerm belongs on the host; Ghostty and Zed run via WSLg.
  environment.systemPackages = darwinPackageParity ++ (with pkgs; [
    binutils
    cmake
    cosmocc
    coreutils-full
    es
    gawk
    gcc
    halloy
    ghostty
    gnumake
    jq
    ldc
    # Shared dotfile scripts require these modules even when their caller
    # scrubs LUA_PATH/LUA_CPATH, so bake them into LuaJIT's own search path.
    (luajit.withPackages (ps: with ps; [
      alt-getopt
      basexx
      busted
      cjson
      lpeg
      lua_cliargs
      luabitop
      luacheck
      luafilesystem
      luasocket
      luasystem
      moonscript
      penlight
      sqlite
      tl
    ]))
    # LuaRocks vendors compat53 files that collide with the canonical module
    # when flattened into the LuaJIT environment. Expose only its CLI here.
    (writeShellApplication {
      name = "luarocks";
      text = ''exec ${luajitPackages.luarocks}/bin/luarocks "$@"'';
    })
    luajitPackages.moonscript
    meson
    ninja
    nushell
    openssh
    pkg-config
    zed-editor
    zellij
    sniffnet
    zip
  ]);

  # This system was first installed from the NixOS-WSL 26.05 image.
  system.stateVersion = "26.05";
}
