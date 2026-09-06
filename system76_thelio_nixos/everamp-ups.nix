{ config, lib, pkgs, herdrPackage, ... }:
let
  cfg = config.services.everamp-monitor;
  lua = pkgs.luajit.withPackages (ps: [ ps.cjson ]);
  nut = config.power.ups.package;
  mode = if cfg.shutdownEnabled then "ARMED" else "OBSERVATION ONLY: automatic shutdown disabled";
  userNotice = pkgs.writeShellScript "everamp-user-notice" ''
    event="$1"
    message="$2"
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
    export XDG_RUNTIME_DIR=/run/user/1000
    export HERDR_SOCKET_PATH=/home/pmarreck/.config/herdr/herdr.sock
    ${pkgs.coreutils}/bin/timeout 5 ${pkgs.libnotify}/bin/notify-send \
      --urgency=critical --expire-time=0 'Thelio UPS' "$message" || true
    ${pkgs.coreutils}/bin/timeout 5 ${herdrPackage}/bin/herdr notification show \
      'Thelio UPS' --body "$message" --sound request || true
    for recipient in peter einstein; do
      ${pkgs.coreutils}/bin/timeout 15 ${config.services.unix-mail-redux.package}/bin/post \
        to "$recipient" --as ups --subject "Thelio UPS: $event" --body "$message" --yes || true
    done
    # Durable per-project notes reach active agent hooks without editing any
    # human's draft. An idle harness may not consume its note until reactivated.
    writer=/home/pmarreck/Code/llm_skills/llmsend/scripts/write-note
    if test -x "$writer"; then
      ${pkgs.coreutils}/bin/timeout 5 ${herdrPackage}/bin/herdr agent list |
        ${pkgs.jq}/bin/jq -r '.result.agents[] | .cwd // empty' |
        ${pkgs.coreutils}/bin/sort -u |
        while IFS= read -r project; do
          case "$project" in /home/pmarreck|/home/pmarreck/*) ;; *) continue ;; esac
          test -d "$project" || continue
          printf '%s\n' "$message" | ${pkgs.coreutils}/bin/timeout 5 "$writer" \
            --inbox "$project/inbox" --sender ups@thelio-nixos \
            --recipient "$(basename "$project")" --subject "Thelio UPS: $event" \
            --description "$message" --type status --priority urgent \
            --response-expected false --tag ups --tag power-outage || true
        done
    fi
  '';
  notify = pkgs.writeShellScript "everamp-notify" ''
    set -eu
    case "$1" in
      on-battery) message='Utility power lost. Running on UPS. Save work; host shutdown deadline is 10 minutes after outage detection.' ;;
      five-minutes) message='UPS outage has lasted 5 minutes. Checkpoint work and stop builds now. Host shutdown deadline: 5 minutes remaining.' ;;
      shutdown) message='UPS outage has reached 10 minutes. Host shutdown is due now; enclosure and cooling fan power must stay on.' ;;
      online) message='Utility power restored. Outage countdown canceled.' ;;
      communication-lost) message='UPS telemetry unavailable or ambiguous. This alone does not prove a power outage. Any previously confirmed outage countdown continues.' ;;
      communication-restored) message='UPS telemetry restored.' ;;
      *) exit 2 ;;
    esac
    message="[$(${pkgs.coreutils}/bin/date --iso-8601=seconds)] $message [${mode}]"
    printf '%s\n' "$message"
    # Login accounting misses many GUI/Herdr PTYs. Write output (never input)
    # to Peter-owned pseudo-terminals, each with a strict timeout.
    ${pkgs.findutils}/bin/find /dev/pts -mindepth 1 -maxdepth 1 -type c -user pmarreck -print0 |
      while IFS= read -r -d $'\0' terminal; do
        ${pkgs.coreutils}/bin/timeout 0.2 ${pkgs.bash}/bin/bash -c \
          'printf "\r\n[Thelio UPS] %s\r\n" "$1" > "$2"' _ "$message" "$terminal" || true
      done
    ${pkgs.util-linux}/bin/runuser -u pmarreck -- ${userNotice} "$1" "$message"
  '';
  enqueue = pkgs.writeShellScript "everamp-enqueue-notice" ''
    exec ${pkgs.systemd}/bin/systemctl --no-block start "everamp-notice@$1.service"
  '';
in {
  options.services.everamp-monitor.shutdownEnabled = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Arm host-only shutdown after 600 seconds on UPS; enable after attended mains-loss verification.";
  };

  config = {
  power.ups = {
    enable = true;
    mode = "standalone";
    openFirewall = false;
    upsd.listen = [ { address = "127.0.0.1"; } ];
    # Our monotonic policy owns the host deadline. No automatic UPS output
    # shutdown: both drive dock and cooling fan lose their soft-switch state.
    upsmon.enable = false;
    upsmon.settings.POWERDOWNFLAG = null;
    ups.everamp = {
      driver = "usbhid-ups";
      port = "auto";
      description = "EverAmp 1500VA/1000W LiFePO4";
      shutdownOrder = -1;
      directives = [
        "vendorid = 06da"
        "productid = ffff"
        "vendor = -BMS-"
        "product = Smart-Battery"
        "pollonly"
        "pollfreq = 2"
      ];
    };
  };

  # Supervise the actual driver so USB reconnection/restarts don't leave an
  # orphaned daemon. Never use a fixed bus, device number, or physical port.
  systemd.services.upsdrv.serviceConfig = {
    Type = lib.mkForce "simple";
    RemainAfterExit = lib.mkForce false;
    ExecStart = lib.mkForce "${nut}/bin/usbhid-ups -F -a everamp -u root";
    Restart = "on-failure";
    RestartSec = 5;
  };

  systemd.services.everamp-monitor = {
    description = "Thelio UPS 0/5/10-minute outage policy";
    after = [ "upsd.service" "upsdrv.service" ];
    environment = {
      UPS_POLICY = toString ./ups/policy.lua;
      UPS_QUERY = "${pkgs.coreutils}/bin/timeout 3 ${nut}/bin/upsc everamp@127.0.0.1 ups.status";
      UPS_NOTIFY = toString enqueue;
      UPS_POWEROFF = "${pkgs.systemd}/bin/systemctl --no-block poweroff";
      UPS_SHUTDOWN_ENABLED = if cfg.shutdownEnabled then "1" else "0";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lua}/bin/luajit ${./ups/monitor.lua}";
      StateDirectory = "everamp-monitor";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "everamp-monitor";
      RuntimeDirectoryMode = "0755";
      RuntimeDirectoryPreserve = true;
      TimeoutStartSec = 15;
    };
  };
  systemd.timers.everamp-monitor = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = 30; OnUnitInactiveSec = 5; AccuracySec = 1; };
  };
  systemd.services."everamp-notice@" = {
    description = "Deliver Thelio UPS event %i";
    path = [ lua pkgs.coreutils pkgs.bash pkgs.jq pkgs.gnused ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${notify} %i";
      TimeoutStartSec = 240;
    };
  };
  environment.systemPackages = [ (pkgs.writeShellScriptBin "ups-status" ''
    exec ${pkgs.bash}/bin/bash ${./ups/status.sh} \
      ${nut}/bin/upsc ${pkgs.jq}/bin/jq ${pkgs.coreutils}/bin/timeout \
      ${./ups/status.jq} ${./ups/status-format.jq} /run/everamp-monitor/status.json "$@"
  '') ];
  };
}
