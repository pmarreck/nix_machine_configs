{ package, operator, home, inbox, lib }:
let
  service = mode: {
    description = "Bounded host snapshot and existing-agent review";
    unitConfig = {
      ConditionUser = operator;
      ConditionPathExists = "%h/.config/mechatron-checkup/config.json";
      ConditionPathIsDirectory = inbox;
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${package}/bin/mechatron-checkup ${mode} --config %h/.config/mechatron-checkup/config.json";
      TimeoutStartSec = 120;
      UMask = "0077";
      StateDirectory = "mechatron-checkup";
      StateDirectoryMode = "0700";
      NoNewPrivileges = true;
      # Filesystem namespacing hides host ZFS pools from this user service.
      # Stay unprivileged, with fixed read-only probes and bounded effects.
      ProtectSystem = false;
      ProtectHome = false;
      ReadWritePaths = [];
      # Observe the host's real /tmp, not a private empty service namespace.
      PrivateTmp = false;
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      Nice = 15;
      IOSchedulingClass = "idle";
      MemoryMax = "256M";
      CPUQuota = "25%";
    };
    environment = {
      HOME = home;
      # The driver utility and private mail CLI come from the host, not a
      # second GPU driver or a separately configured mail installation.
      PATH = lib.mkForce "${home}/bin:${home}/dotfiles/bin:/run/current-system/sw/bin:/run/wrappers/bin";
    };
  };
in {
  systemd.user.services.mechatron-checkup = service "--run";
  systemd.user.services.mechatron-checkup-delivery = service "--deliver";
  systemd.user.timers.mechatron-checkup = {
    description = "Inspect host resources every three hours";
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionUser = operator;
    timerConfig = {
      OnCalendar = "*-*-* 00/3:00:00";
      Persistent = true;
      AccuracySec = "1m";
      Unit = "mechatron-checkup.service";
    };
  };
  systemd.user.timers.mechatron-checkup-delivery = {
    description = "Retry pending checkup delivery to an idle native thread";
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionUser = operator;
    timerConfig = {
      OnCalendar = "minutely";
      Persistent = true;
      Unit = "mechatron-checkup-delivery.service";
    };
  };
}
