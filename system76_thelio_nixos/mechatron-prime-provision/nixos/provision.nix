{ config, lib, pkgs, ... }:
let
  cfg = config.services.mechatronPrimeProvision;
  broker = import ../nix/provision-package.nix { inherit pkgs; };
in {
  options.services.mechatronPrimeProvision = {
    enable = lib.mkEnableOption "credential-isolated Mechatron Prime webhook provisioning";
    operator = lib.mkOption { type = lib.types.str; description = "Local account allowed to use the provisioning socket."; };
    endpoint = lib.mkOption { type = lib.types.strMatching "https://[^[:space:]]+"; description = "Fixed existing CI webhook endpoint."; };
    webhookEnvironmentFile = lib.mkOption { type = lib.types.str; default = "/etc/mechatron-prime/github-webhook.env"; };
    githubTokenFile = lib.mkOption { type = lib.types.str; default = "/etc/mechatron-prime/github-provision-token"; };
  };
  config = lib.mkIf cfg.enable {
    systemd.sockets.mechatron-prime-provision = {
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "/run/mechatron-prime-provision.sock";
        SocketUser = cfg.operator;
        SocketMode = "0600";
        RemoveOnStop = true;
        Backlog = 8;
      };
    };
    systemd.services.mechatron-prime-provision = {
      description = "Mechatron Prime credential-isolated webhook provisioner";
      wantedBy = [ "multi-user.target" ];
      requires = [ "mechatron-prime-provision.socket" ];
      after = [ "network-online.target" "mechatron-prime-provision.socket" ];
      environment = {
        MECHATRON_PROVISION_ENDPOINT = cfg.endpoint;
        MECHATRON_PROVISION_STATUS = "/run/mechatron-prime-provision/status.json";
        XDG_CONFIG_HOME = "/run/mechatron-prime-provision/config";
      };
      serviceConfig = {
        ExecStart = "${broker}/bin/mechatron-prime-provision";
        DynamicUser = true;
        User = "mechatron-prime-provision";
        LoadCredential = [ "webhook-env:${cfg.webhookEnvironmentFile}" "github-token:${cfg.githubTokenFile}" ];
        RuntimeDirectory = "mechatron-prime-provision";
        RuntimeDirectoryMode = "0750";
        UMask = "0027";
        Restart = "on-failure";
        RestartSec = 5;
        KillMode = "control-group";
        TimeoutStopSec = 10;
        MemoryMax = "256M";
        TasksMax = 32;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        CapabilityBoundingSet = "";
      };
    };
  };
}
