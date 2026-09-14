# Ephemeral patch: upstream wezterm PR 7487 (wezterm/wezterm#7230), the
# key-repeat loop that outlives a closed Wayland window. Evaluated on the
# Thelio 2026-09-13/14; evidence in ~/Code/wezterm/eval/REPORT.md.
#
# Expiry logic: the fetched wezterm source is read at evaluation time (an
# import-from-derivation, cheap because the source is a fixed-output fetch).
# If upstream already carries the guard, the patch is skipped and a warning is
# printed during evaluation, so `nixos-rebuild` shows it. If the guard is
# absent but the patch no longer applies, the build warns and continues
# without it instead of failing. Delete this file and its entry in
# `nixpkgs.overlays` once the warning appears.
final: prev:
let
  # Vendored copy of ~/Code/wezterm/eval/pr7487.patch (pure evaluation cannot
  # read outside this flake). Keep the fork copy as the source of truth.
  patch = ./patches/wezterm-pr7487.patch;
  marker = "key repetition cancelled because window has been closed";
  file = "window/src/os/wayland/window.rs";
  src = prev.wezterm.src;
  rev = if builtins.isAttrs src then (src.rev or "unknown revision") else "unknown revision";
  upstreamHasGuard = prev.lib.hasInfix marker (builtins.readFile "${src}/${file}");
in
{
  wezterm =
    if upstreamHasGuard then
      prev.lib.warn
        "wezterm: upstream source ${rev} already contains the PR 7487 guard; ${toString patch} not applied. Remove wezterm-pr7487-overlay.nix from nixpkgs.overlays."
        prev.wezterm
    else
      prev.wezterm.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          if patch --forward -p1 --dry-run < ${patch} >/dev/null 2>&1; then
            patch --forward -p1 < ${patch}
            echo "wezterm: applied PR 7487 patch ${patch}"
          else
            echo "WARNING: wezterm: PR 7487 patch no longer applies to ${rev} and the guard is absent; building WITHOUT it. Re-evaluate ${patch}." >&2
          fi
        '';
      });
}
