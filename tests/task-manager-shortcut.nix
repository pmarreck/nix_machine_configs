{ pkgs }:
let
  primary = pkgs.writeShellScriptBin "tmog-task-manager" ''
    printf 'tmog:%s\n' "$@"
  '';
  fallback = pkgs.writeShellScriptBin "gnome-system-monitor" ''
    printf 'gnome:%s\n' "$@"
  '';
  absent = pkgs.runCommand "absent-task-manager" { } ''mkdir -p "$out/bin"'';
  nonExecutable = pkgs.runCommand "non-executable-task-manager" { } ''
    mkdir -p "$out/bin"
    touch "$out/bin/tmog-task-manager"
  '';
  launcher = tmog: pkgs.callPackage ../packages/task-manager-launcher.nix {
    tmogExecutable = "${tmog}/bin/tmog-task-manager";
    gnome-system-monitor = fallback;
  };
in
pkgs.runCommand "task-manager-shortcut-tests" { } ''
  test "$(${launcher primary}/bin/open-task-manager 'two words')" = 'tmog:two words'
  test "$(${launcher absent}/bin/open-task-manager 'two words')" = 'gnome:two words'
  test "$(${launcher nonExecutable}/bin/open-task-manager 'two words')" = 'gnome:two words'
  touch "$out"
''
