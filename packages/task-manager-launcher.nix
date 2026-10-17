{ lib, writeShellScriptBin, tmogExecutable, gnome-system-monitor }:
writeShellScriptBin "open-task-manager" ''
  # GUI shortcuts do not inherit interactive-shell PATH. Use the installed
  # profile path for optional TMOG, keeping only the fallback in our closure.
  if [ -x ${lib.escapeShellArg tmogExecutable} ]; then
    exec ${lib.escapeShellArg tmogExecutable} "$@"
  fi
  exec ${gnome-system-monitor}/bin/gnome-system-monitor "$@"
''
