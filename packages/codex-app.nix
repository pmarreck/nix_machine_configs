{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  buildFHSEnv,
}:

let
  version = "26.810.41047";

  payload = stdenv.mkDerivation {
    pname = "codex-app-payload";
    inherit version;

    src = fetchurl {
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_26.810.41047_amd64.deb";
      hash = "sha256-eHFfo80Tb/ZwcNqnaBmtrsxbQumYUVWWWWRdzh+/KvM=";
    };

    nativeBuildInputs = [ dpkg ];

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x "$src" .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib" "$out/share"
      cp -a usr/lib/chatgpt "$out/lib/"
      cp -a usr/share/applications "$out/share/"
      cp -a usr/share/pixmaps "$out/share/"
      runHook postInstall
    '';
  };

  app = buildFHSEnv {
    name = "chatgpt";

    # The official payload includes Electron, native Node modules, helper
    # binaries, and architecture-specific fallbacks. Keeping those binaries
    # intact inside a Nix-built FHS runtime avoids selectively rewriting only
    # the files that autoPatchelf happens to recognize.
    targetPkgs = pkgs: with pkgs; [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      atk
      cairo
      cups
      dbus
      expat
      fontconfig
      freetype
      gcc.cc.lib
      gdk-pixbuf
      glib
      graphite2
      gtk3
      harfbuzz
      icu
      libdrm
      libgbm
      libnotify
      libsecret
      libusb1
      libva
      libxkbcommon
      mesa
      nspr
      nss
      openssl
      pango
      systemd
      wayland
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

    runScript = "${payload}/lib/chatgpt/ChatGPT";

    extraInstallCommands = ''
      mkdir -p "$out/share/applications" "$out/share/pixmaps"
      cp -a ${payload}/share/applications/chatgpt.desktop \
        "$out/share/applications/chatgpt.desktop"
      cp -a ${payload}/share/pixmaps/chatgpt.png \
        "$out/share/pixmaps/chatgpt.png"
    '';
  };
in
app.overrideAttrs (old: {
  pname = "codex-app";
  inherit version;

  passthru = (old.passthru or { }) // {
    inherit payload;
  };

  meta = (old.meta or { }) // {
    description = "Official OpenAI Codex app for Linux";
    homepage = "https://developers.openai.com/codex/app";
    license = lib.licenses.unfree;
    mainProgram = "chatgpt";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
