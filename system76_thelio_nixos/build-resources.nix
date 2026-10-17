{ config, pkgs, ... }:
let
	tools = pkgs.callPackage ../packages/build-resources.nix { };
in
{
	# Direct devShell builds are not children of nix-daemon's builder envelope.
	# Keep their kill domains separate from the terminal server and agent clients.
	users.users.${config.services.unix-mail-redux.owner}.packages = [ tools ];
	systemd.user.slices.agentbuilds = {
		description = "Shared native build and test memory budget";
		sliceConfig = {
			MemoryHigh = "24G";
			MemoryMax = "32G";
			MemorySwapMax = "2G";
			CPUWeight = 20;
			IOWeight = 20;
		};
	};
	systemd.user.services.build-oom-watch = {
		description = "Attribute kernel memory kills to jobs or host exhaustion";
		wantedBy = [ "default.target" ];
		unitConfig.ConditionUser = config.services.unix-mail-redux.owner;
		serviceConfig = {
			ExecStart = "${tools}/bin/build-oom-watch";
			Restart = "always";
			RestartSec = 5;
			UMask = "0077";
			MemoryMax = "128M";
			Nice = 10;
		};
	};
}
