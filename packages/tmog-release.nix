# The generic version.txt and old Linux URL no longer describe the same release.
# Consume one platform manifest so version, artifact and checksum stay together.
{ manifest }:
let
  version = manifest.version or "";
  artifact = manifest.artifact or "";
  sha256 = manifest.sha256 or "";
  valid = (manifest.schemaVersion or null) == 1
    && (manifest.platform or null) == "Linux"
    && (manifest.architecture or null) == "x86_64"
    && builtins.isString version
    && builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+" version != null
    && artifact == "/downloads/TaskManagerOG-${version}-x86_64.AppImage"
    && builtins.isString sha256
    && builtins.match "[a-fA-F0-9]{64}" sha256 != null;
in
if !valid then
  throw "Invalid TMOG Linux x86_64 manifest: expected matching versioned AppImage and SHA-256"
else {
  inherit version sha256;
  url = "https://tmog.org${artifact}";
}
