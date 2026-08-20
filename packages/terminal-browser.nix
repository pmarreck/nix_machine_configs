{
  lib,
  stdenv,
  fetchurl,
  buildFHSEnv,
}:

let
  version = "0.5.8";

  source = fetchurl {
    url = "https://github.com/zenbu-labs/terminal-browser/releases/download/v${version}/terminal-browser-linux-x64.tar.gz";
    hash = "sha256-wzC+M0Hvb2yxBuT7MsHWB1Sgjhp2QRQ6empNnpRI9hc=";
  };

  payload = stdenv.mkDerivation {
    pname = "terminal-browser-payload";
    inherit version;

    dontUnpack = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib/terminal-browser"
      tar -xzf ${source} \
        --strip-components 1 \
        -C "$out/lib/terminal-browser"

      # Upstream's `upgrade` command downloads an installer and pipes it into
      # Bash. The Nix generation owns this immutable application tree.
      substituteInPlace "$out/lib/terminal-browser/cli/dist/main.js" \
        --replace-fail \
          'if (command === "upgrade") return upgradeCommand();' \
          'if (command === "upgrade") throw new Error("this Terminal Browser install is managed by Nix; update /etc/nixos instead");'

      patchShebangs "$out/lib/terminal-browser/bin"

      runHook postInstall
    '';
  };

  app = buildFHSEnv {
    name = "terminal-browser";

    # The official release includes Electron, a native Node pixel renderer,
    # and agent-browser. Keep those matched binaries together and supply their
    # Linux ABI through a declarative FHS environment.
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

    profile = ''
      export TERMINAL_BROWSER_DIST_ROOT="${payload}/lib/terminal-browser"
    '';

    runScript = "${payload}/lib/terminal-browser/bin/terminal-browser";
  };
in
app.overrideAttrs (old: {
  pname = "terminal-browser";
  inherit version;

  passthru = (old.passthru or { }) // {
    inherit payload;
  };

  meta = (old.meta or { }) // {
    description = "Chromium browser rendered through the Kitty terminal graphics protocol";
    homepage = "https://terminal-browser.com/";
    license = lib.licenses.mit;
    mainProgram = "terminal-browser";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
