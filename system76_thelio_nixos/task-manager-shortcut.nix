{ lib, pkgs, ... }:
let
  launcher = pkgs.callPackage ../packages/task-manager-launcher.nix {
    tmogExecutable = "/etc/profiles/per-user/pmarreck/bin/tmog-task-manager";
  };
  shortcutPath = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/task-manager/";
in
{
  # Ctrl-Alt-Delete opens TMOG, falling back to GNOME System Monitor when its
  # executable is unavailable. This replaces GNOME's power/logout shortcut,
  # not the kernel/systemd handling of Ctrl-Alt-Delete on a virtual console.
  programs.dconf.profiles.user.databases = [{
    settings = {
      "org/gnome/settings-daemon/plugins/media-keys" = {
        logout = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
        custom-keybindings = [ shortcutPath ];
      };
      "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/task-manager" = {
        name = "Task Manager (TMOG, GNOME fallback)";
        command = "${launcher}/bin/open-task-manager";
        binding = "<Control><Alt>Delete";
      };
    };
  }];
  system.build.taskManagerShortcut = launcher;
  system.build.taskManagerShortcutTests = import ../tests/task-manager-shortcut.nix { inherit pkgs; };
}
