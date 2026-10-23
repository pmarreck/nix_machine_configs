{ pkgs, llmsendSource }:
let
  source = pkgs.runCommand "mechatron-checkup-source" {} ''
    mkdir -p "$out/ops"
    cp -R ${../watch} "$out/watch"
    cp -R ${../notifications} "$out/notifications"
    cp ${../ops/probes.lua} "$out/ops/probes.lua"
  '';
in pkgs.writeShellApplication {
  name = "mechatron-checkup";
  runtimeInputs = [
    pkgs.coreutils pkgs.procps pkgs.systemd pkgs.websocat
    (pkgs.luajit.withPackages (p: [ p.cjson p.luafilesystem ]))
    llmsendSource.packages.${pkgs.stdenv.hostPlatform.system}.writeNote
  ];
  text = ''
    export LLMSEND_NATIVE_DIR=${llmsendSource}/skills/llmsend/scripts
    exec luajit ${source}/watch/main.lua "$@"
  '';
}
