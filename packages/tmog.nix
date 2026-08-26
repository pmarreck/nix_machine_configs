{ appimageTools, lib, src, version }:

let
  pname = "tmog-task-manager";
  contents = appimageTools.extractType2 {
    inherit pname src version;
  };
in
appimageTools.wrapType2 {
  inherit pname src version;

  extraInstallCommands = ''
    install -m 444 -D \
      ${contents}/com.tmog.taskmanager.desktop \
      $out/share/applications/com.tmog.taskmanager.desktop
    cp -r ${contents}/usr/share/icons $out/share/
    cp -r ${contents}/usr/share/metainfo $out/share/
    cp -r ${contents}/usr/share/pixmaps $out/share/
  '';

  passthru.updateCommand = "nix flake update tmog-version tmog-linux";

  meta = {
    description = "Native system monitor and task manager";
    homepage = "https://tmog.org";
    license = lib.licenses.unfree;
    mainProgram = "tmog-task-manager";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
