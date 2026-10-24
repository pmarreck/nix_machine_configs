{ pkgs, lib ? pkgs.lib }:
let
	deps = [ pkgs.coreutils pkgs.findutils pkgs.gawk pkgs.jq pkgs.systemd pkgs.util-linux pkgs.libnotify ];
	wrap = name: pkgs.writeShellScriptBin name ''
		export PATH="${lib.makeBinPath deps}:$PATH"
		${lib.optionalString (name == "build-budget") (builtins.readFile ../scripts/admission_priority.bash)}
		${lib.optionalString (name == "build-budget") "export BUILD_BUDGET_RM=\"${pkgs.coreutils}/bin/rm\"\n"}${builtins.readFile (../scripts + "/${name}")}
	'';
in pkgs.symlinkJoin {
	name = "build-resources-1.0";
	paths = [ (wrap "build-budget") (wrap "build-oom-watch") ];
}
