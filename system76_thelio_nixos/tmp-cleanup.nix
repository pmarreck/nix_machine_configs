{ pkgs, ... }:
let
	cleanup = pkgs.writeText "tmp-cleanup" (builtins.readFile ../scripts/tmp-cleanup);
in
{
	systemd.services.tmp-cleanup = {
		description = "Delete inactive ephemeral temporary files";
		path = [ pkgs.coreutils pkgs.findutils ];
		environment = {
			TMP_CLEANUP_RM = "${pkgs.coreutils}/bin/rm";
			TMP_CLEANUP_UNLINK = "${pkgs.coreutils}/bin/unlink";
		};
		serviceConfig = {
			Type = "oneshot";
			ExecStart = "${pkgs.util-linux}/bin/flock -n -E 0 /run/tmp-cleanup/pass.lock ${pkgs.bash}/bin/bash ${cleanup}";
			RuntimeDirectory = "tmp-cleanup";
			RuntimeDirectoryMode = "0700";
			UMask = "0077";
			Nice = 15;
			IOSchedulingClass = "idle";
			TimeoutStartSec = "10min";
		};
	};
	systemd.timers.tmp-cleanup = {
		wantedBy = [ "timers.target" ];
		timerConfig = {
			OnCalendar = "hourly";
			Persistent = true;
		};
	};
}
