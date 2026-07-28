# accentd — macOS-style press-and-hold accent popup for Linux.
#
# Hold a vowel for ~300 ms and a numbered popup of accented variants appears;
# pick one to insert it. Upstream: https://github.com/gildo/accentd (MIT, Rust).
#
# Added 2026-07-28 (Einstein) — Peter asked for this. Upstream has no Nix
# package, only an AUR PKGBUILD, so the derivation is ours and lives in
# ./packages/accentd (wired through the ./packages overlay).
#
# HOW IT WORKS — three binaries, deliberately split:
#   accentd        system daemon; grabs keyboards via evdev, runs the
#                  press-and-hold state machine, synthesizes the chosen
#                  character through uinput. Runs as root: it must read every
#                  /dev/input/event* and write /dev/uinput.
#   accentd-popup  per-user GTK4 overlay. Runs in your session, never as root.
#   accentctl      CLI; talks to the daemon over a Unix socket.
# They speak JSON-lines over /run/accentd/accentd.sock, which the daemon
# chmods 0666 so the unprivileged popup can connect.
#
# ⚠ KNOWN LIMITATION ON THIS HOST — read before judging it broken.
# The popup positions itself using wlr-layer-shell. GNOME does not implement
# that protocol and has declined to, so on GNOME Wayland (what this machine
# runs: GDM + GNOME, XDG_SESSION_TYPE=wayland) the popup degrades to an
# ordinary undecorated GTK4 window with, in upstream's own words, "degraded
# positioning" — it appears, but is not pinned to the text caret. That is
# upstream README §"GNOME Wayland", not a packaging defect. Sway, Hyprland and
# KDE Wayland get the properly positioned overlay.
#
# AFTER `ixnay reify`:
#   systemctl status accentd                  # system daemon
#   systemctl --user status accentd-popup     # your session's popup
#   accentctl status
#   accentctl set-locale fr                   # runtime override; it|es|fr|de|pt
# Then hold a vowel in any text field for ~300 ms.

{ lib, pkgs, ... }:

let
  # Upstream's default is "it" (the author is Italian). "fr" is the richest of
  # the five shipped sets for general US-English use: the only one carrying æ,
  # œ and ÿ alongside the usual grave/acute/circumflex/diaeresis vowels and ç.
  # Change this one word and reify to switch. Full list: it | es | fr | de | pt.
  activeLocale = "fr";
in
{
  environment.systemPackages = [ pkgs.accentd ];

  # Loads the uinput kernel module and installs the /dev/uinput udev rule.
  # This replaces upstream's dist/70-accentd.rules, which is the same rule
  # written by hand. The daemon runs as root, so the node's group ownership
  # does not gate it — the MODULE LOAD is the part that actually matters.
  # Without it the daemon starts cleanly and then cannot synthesize a single
  # keystroke, which looks like "the popup does nothing".
  hardware.uinput.enable = true;

  # Deliberately NOT adding pmarreck to the "input" group. Upstream's install
  # notes say to, but that advice is for running the daemon as an ordinary
  # user. Here it runs as root under systemd, so the membership buys nothing —
  # and "input" grants raw read access to every keyboard event device, i.e. a
  # standing keylogging surface for anything running as that user. Zero
  # functional gain is not worth that trade.

  # The daemon reads $XDG_CONFIG_HOME/accentd/config.toml at startup. Pointing
  # that at /etc makes the config declarative here rather than hiding in root's
  # home — which ProtectHome=yes would make unreadable anyway.
  environment.etc."accentd/config.toml".text = ''
    [general]
    threshold_ms = 300
    enabled = true

    [popup]
    font_size = 24
    timeout_ms = 5000

    # MUST STAY false. Upstream defaults this to true in BOTH config.default.toml
    # and the code (PopupConfig::default_keep_open), and it is broken:
    # state_machine.rs handle_popup(), "Release of the held key" — with
    # keep_open the daemon returns Action::Suppress for the key-UP of the held
    # key, while its key-DOWN was already relayed. The compositor therefore
    # never sees the release and the key is logically stuck down, producing an
    # auto-repeat storm and wedging subsequent keystrokes.
    # Observed live 2026-07-28: Peter got "aluuûuüuu" and a dead Delete key
    # within a minute of activation.
    keep_open = false

    [locale]
    active = "${activeLocale}"
  '';

  systemd.services.accentd = {
    description = "Accent character daemon (press-and-hold popup)";

    # DELIBERATELY NOT auto-started. `wantedBy = [ "multi-user.target" ]` was
    # here and is removed on purpose: this daemon takes an EXCLUSIVE evdev grab
    # of every keyboard, so any bug in it degrades or kills real typing — which
    # it did on 2026-07-28, first try. A thing that can brick input must be
    # opted into per boot, not silently armed at startup.
    #
    # Start it when you actually want it:
    #     sudo systemctl start accentd && systemctl --user start accentd-popup
    # Stop it the moment it misbehaves:
    #     sudo systemctl stop accentd
    # Note `systemctl disable` does NOT stick on NixOS — activation recreates
    # the .wants symlinks — so absence of wantedBy here is the real control.
    after = [ "systemd-logind.service" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = lib.getExe' pkgs.accentd "accentd";
      Restart = "on-failure";
      RestartSec = 3;

      # Creates /run/accentd for the socket. The daemon hardcodes
      # /run/accentd/accentd.sock, so this directory name is load-bearing.
      RuntimeDirectory = "accentd";

      Environment = [ "XDG_CONFIG_HOME=/etc" ];

      # Hardening, carried over from upstream's unit. Note what is ABSENT:
      # PrivateDevices would hide /dev/input and /dev/uinput and break the
      # daemon completely, so it must stay off.
      ProtectHome = true;
      ProtectSystem = "strict";
      NoNewPrivileges = true;
      PrivateTmp = true;
      RestrictRealtime = true;
      LockPersonality = true;
      ProtectHostname = true;
      ProtectClock = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
    };
  };

  systemd.user.services.accentd-popup = {
    description = "Accent character popup (accentd UI)";
    # Also not auto-started — it is useless without the daemon, and the daemon
    # is opt-in. partOf still ties its lifetime to the session once started.
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = lib.getExe' pkgs.accentd "accentd-popup";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
