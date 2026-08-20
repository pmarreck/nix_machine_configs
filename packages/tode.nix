{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  buildFHSEnv,
  makeDesktopItem,
}:

let
  version = "0.1.13";

  todeSource = fetchurl {
    url = "https://github.com/zenbu-labs/terminal-code/releases/download/v${version}/tode-linux-x64.tar.gz";
    hash = "sha256-zMKgw6nCV/xCztd+bxtM5SugzBxFKaYB9lV6Uku00XM=";
  };

  # Terminal Code injects into a version-specific code-server workbench. Its
  # own release pins 4.132.0 and this exact asset hash, so package that runtime
  # instead of allowing the first launch to download mutable user state.
  codeServerSource = fetchurl {
    url = "https://github.com/coder/code-server/releases/download/v4.132.0/code-server-4.132.0-linux-amd64.tar.gz";
    hash = "sha256-o40m9MuB92j+3f954pN/0/Ocg9Pai+PaciXhCH5i5O0=";
  };

  payload = stdenv.mkDerivation {
    pname = "tode-payload";
    inherit version;

    dontUnpack = true;
    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib"
      tar -xzf ${todeSource} -C "$out/lib"
      mkdir -p "$out/lib/code-server"
      tar -xzf ${codeServerSource} \
        --strip-components 1 \
        -C "$out/lib/code-server"

      # `--upgrade --check` remains useful. Mutation and removal belong to the
      # Nix generation, though, so fail before Terminal Code tries to replace
      # or delete its immutable store path.
      substituteInPlace "$out/lib/tode/dist/main.js" \
        --replace-fail \
          'return upgradeCommand(args.slice(1));' \
          'if (!args.slice(1).includes("--check")) throw new Error("this Terminal Code install is managed by Nix; update /etc/nixos instead"); else return upgradeCommand(args.slice(1));' \
        --replace-fail \
          'return (0, uninstall_1.uninstallCommand)(args.slice(1));' \
          'throw new Error("this Terminal Code install is managed by Nix; remove tode from /etc/nixos instead");'

      wrapProgram "$out/lib/tode/bin/tode" \
        --set TODE_INSTALL_ROOT "$out/lib/tode" \
        --set TODE_CODE_SERVER "$out/lib/code-server/bin/code-server"

      runHook postInstall
    '';
  };

  desktopItem = makeDesktopItem {
    name = "tode";
    desktopName = "Terminal Code";
    comment = "VS Code in a terminal";
    exec = "tode";
    icon = "tode";
    terminal = true;
    categories = [ "Development" "TextEditor" ];
  };

  app = buildFHSEnv {
    name = "tode";

    # Upstream ships Electron, a native Node module, agent-browser, and the
    # matching code-server binary. Keep those vendor binaries intact inside a
    # declarative FHS runtime instead of executing the apt-oriented installer.
    targetPkgs = pkgs: with pkgs; [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      atk
      bash
      cairo
      coreutils
      cups
      curl
      dbus
      expat
      fontconfig
      freetype
      gcc.cc.lib
      gdk-pixbuf
      git
      glib
      graphite2
      gtk3
      harfbuzz
      icu
      libdrm
      libgbm
      libnotify
      libsecret
      libva
      libxkbcommon
      mesa
      nspr
      nss
      openssl
      pango
      procps
      systemd
      util-linux
      wayland
      which
      xdg-utils
      libx11
      libxscrnsaver
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxi
      libxrandr
      libxrender
      libxtst
      libxcb
      zlib
    ];

    runScript = "${payload}/lib/tode/bin/tode";

    extraInstallCommands = ''
      mkdir -p "$out/share/applications" "$out/share/icons/hicolor/512x512/apps"
      cp ${desktopItem}/share/applications/tode.desktop \
        "$out/share/applications/tode.desktop"
      cp ${payload}/lib/tode/assets/logos/tode.png \
        "$out/share/icons/hicolor/512x512/apps/tode.png"
    '';
  };
in
app.overrideAttrs (old: {
  pname = "tode";
  inherit version;

  passthru = (old.passthru or { }) // {
    inherit payload;
  };

  meta = (old.meta or { }) // {
    description = "Terminal Code, a VS Code workbench rendered in the terminal";
    homepage = "https://terminal-code.com/";
    license = lib.licenses.mit;
    mainProgram = "tode";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
