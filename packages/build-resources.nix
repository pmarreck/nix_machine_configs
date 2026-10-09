{ pkgs, lib ? pkgs.lib }:
let
	deps = [ pkgs.coreutils pkgs.gawk pkgs.jq pkgs.systemd pkgs.util-linux pkgs.libnotify ];
	wrap = name: pkgs.writeShellScriptBin name ''
		export PATH="${lib.makeBinPath deps}:$PATH"
		${builtins.readFile (../scripts + "/${name}")}
	'';
in pkgs.symlinkJoin {
	name = "build-resources-1.0";
	paths = [ (wrap "build-budget") (wrap "build-oom-watch") ];
}
