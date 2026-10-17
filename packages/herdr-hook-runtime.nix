{ pkgs, herdrSource }:
let
  lib = pkgs.lib;
  kinds = [ "claude" "codex" "grok" ];
  hookPath = lib.makeBinPath [ pkgs.python3 pkgs.coreutils pkgs.bash ];
  hooks = pkgs.runCommand "herdr-scoped-hooks" { } ''
    mkdir -p "$out/share/herdr-hooks"
    ${lib.concatMapStringsSep "\n" (kind: ''
      # Keep upstream's version markers and payload handling. The only patch
      # supplies interpreter/tools to this process, never the calling agent.
      sed '/^set -eu$/a export PATH="${hookPath}:''${PATH:-}"' \
        ${herdrSource}/src/integration/assets/${kind}/herdr-agent-state.sh \
        > "$out/share/herdr-hooks/${kind}.sh"
      chmod +x "$out/share/herdr-hooks/${kind}.sh"
    '') kinds}
  '';
  collie = pkgs.writeShellApplication {
    name = "collie-runtime";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      # Keep the vendor's mutable `current` pointer/self-updater, but give only
      # this invocation (and its children) the doctor/hook interpreter.
      exec "''${XDG_DATA_HOME:-$HOME/.local/share}/collie/current/bin/collie" "$@"
    '';
  };
  package = pkgs.symlinkJoin {
    name = "herdr-hook-runtime";
    paths = [ hooks collie ];
    meta.mainProgram = "collie-runtime";
  };
  check = pkgs.runCommand "herdr-hook-runtime-check" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    # Python is solely the test driver here. Each child starts with a PATH
    # containing shell/core tools but no interpreter, just like the live fault.
    python3 ${../tests/herdr_hook_runtime_check.py} \
      ${package} ${herdrSource} ${lib.makeBinPath [ pkgs.bash pkgs.coreutils ]}
    touch "$out"
  '';
in { inherit package check; }
