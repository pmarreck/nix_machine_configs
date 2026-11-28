{ lib, fetchurl, base, tidy }:
# 2026-09-21: 1.21.1 reassigned all 66 internal INBOX messages to their Sent
# copies locally. 1.25.0 includes the upstream Inbox/Sent collision fix:
# https://github.com/Foundry376/Mailspring/releases/tag/1.25.0
# Remove this version override once the pinned nixpkgs provides >= 1.25.0.
# Keep libtidy in the runtime search path until nixpkgs supplies it: mailsync
# loads it dynamically, so autoPatchelf cannot infer that dependency.
base.overrideAttrs (old:
  {
    runtimeDependencies = (old.runtimeDependencies or [ ]) ++ [ (lib.getLib tidy) ];
  } // lib.optionalAttrs (lib.versionOlder base.version "1.25.0") {
    version = "1.25.0";
    src = fetchurl {
      url = "https://github.com/Foundry376/Mailspring/releases/download/1.25.0/mailspring-1.25.0-amd64.deb";
      hash = "sha256-TX9lK+uj8tB4RD4uPFtXvY9Xc1PSiBW6HFUFJZsewfA=";
    };
  })
