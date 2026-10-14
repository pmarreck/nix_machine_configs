{ config, inputs, pkgs, ... }:
let
	package = inputs.llmsend_reminders.packages.${pkgs.stdenv.hostPlatform.system}.inboxRemind;
	operator = config.services.unix-mail-redux.owner;
	privateConfig = "%h/.config/llmsend-reminders/config.json";
in
{
	# The private configuration supplies explicit recipients and the 3600-second
	# reminder interval. This timer only polls deadlines and bounded retries.
	systemd.user.services.llmsend-inbox-remind = {
		description = "Resurface unhandled inbox notes to verified idle native sessions";
		unitConfig = {
			ConditionUser = operator;
			ConditionPathExists = privateConfig;
		};
		serviceConfig = {
			Type = "oneshot";
			ExecStart = "${package}/bin/llmsend-inbox-remind --config ${privateConfig}";
			TimeoutStartSec = 90;
			SuccessExitStatus = [ 3 ];
			UMask = "0077";
			StateDirectory = "llmsend-reminders";
			StateDirectoryMode = "0700";
			NoNewPrivileges = true;
			PrivateTmp = true;
			ProtectSystem = "strict";
			ProtectHome = "read-only";
			RestrictAddressFamilies = [ "AF_UNIX" ];
		};
	};
	systemd.user.timers.llmsend-inbox-remind = {
		description = "Poll hourly inbox-reminder deadlines and bounded retries";
		wantedBy = [ "timers.target" ];
		unitConfig.ConditionUser = operator;
		timerConfig = {
			OnCalendar = "minutely";
			Persistent = true;
			Unit = "llmsend-inbox-remind.service";
		};
	};
}
