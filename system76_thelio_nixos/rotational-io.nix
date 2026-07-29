# I/O scheduling for rotational media, plus one cosmetic audio fix.
#
# Added 2026-07-28 (Einstein) after an evening of UI stalls that were blamed, in
# order, on CI, I/O contention, swap, Mailspring, Firefox and codescan — all of
# which measurement refuted. This is what actually held up.
#
# ── THE FINDING ─────────────────────────────────────────────────────────────
# rpool (`/`, `/home`, `/var`) is a 7200rpm WD101FZBX mirror behind a USB dock.
# The kernel had it as:
#
#     sdd  sched=[none] mq-deadline kyber   rotational=1   nr_requests=30
#
# `none` is the correct default for NVMe, where reordering buys nothing because
# there is no seek penalty. It is applied here to media that very much has one.
#
# Peter's objection is what led to this, and it was the right question:
# computers ran ZFS on spinning rust for decades without this problem, so why
# now? The answer is not that the disks got slower. It is that for all those
# decades the block layer ran CFQ / deadline / BFQ, which **merge and reorder
# requests to minimise seeks** and enforce read-latency fairness so a write
# burst cannot starve interactive reads. With `none`, requests reach the platter
# in submission order: maximum seeking, and no anti-starvation at all. Modern
# I/O defaults assume flash; this hardware is not flash.
#
# Measured during an actual stall, before the fix: sdd at 97% utilisation,
# ~800 reads/s of ~9.7 KB, queue depth 30, and **flush latency 141-192 ms** —
# while its mirror twin sde sat at 1%. A 150 ms fsync is a visible UI freeze.
#
# BFQ over mq-deadline because this is an interactive desktop: BFQ explicitly
# prioritises latency-sensitive interactive tasks over background throughput,
# which is exactly the failure mode here (a Nix build freezing GNOME).
#
# NOT a substitute for `~/Code/THELIO_DRIVE_MIGRATION.md`. Moving these off USB
# onto internal SATA remains the real fix; this makes the interim tolerable.
#
# Verify after a rebuild:
#     cat /sys/block/sdd/queue/scheduler     # -> [bfq]
#     cat /sys/block/sdd/queue/nr_requests   # -> 256

{ ... }:

{
  # Match on ROTATIONAL, not on device name: sdd/sde are USB and their letters
  # can change across enumeration. Keyed on the property that actually matters,
  # so it stays correct if the dock re-enumerates or a disk is added.
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/nr_requests}="256"
  '';

  boot.kernelModules = [ "bfq" ];

  # ── Cosmetic: the Klipsch speakers ────────────────────────────────────────
  # They are R-15PM. The device's USB string descriptor is corrupt — byte 0xFF
  # ("ÿ") where the "5" belongs — so ALSA, PipeWire and the GNOME sound menu all
  # faithfully render "Klipsch R-1ÿPM". It is wrong at the source and cannot be
  # fixed there, but the presentation layer is ours.
  services.pipewire.wireplumber.extraConfig."51-klipsch-name" = {
    "monitor.alsa.rules" = [
      {
        matches = [ { "device.name" = "alsa_card.usb-Sonicstar_Klipsch_R-1__PM-01"; } ];
        actions.update-props = {
          "device.description" = "Klipsch R-15PM";
          "device.nick" = "Klipsch R-15PM";
        };
      }
      {
        matches = [ { "node.name" = "~alsa_output.usb-Sonicstar_Klipsch_R-1__PM-01.*"; } ];
        actions.update-props = {
          "node.description" = "Klipsch R-15PM";
          "node.nick" = "Klipsch R-15PM";
        };
      }
    ];
  };
}
