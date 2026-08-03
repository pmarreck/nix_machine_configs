{ config, pkgs, ... }:

{ boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "a3e8353c";
  # Explicit (silences the 26.11 warning whose new default is false). Kept true:
  # this is a single-host root pool, so force-importing lets it mount after an
  # unclean shutdown (e.g. power loss) instead of dropping to an unbootable
  # prompt. The data-loss risk of `true` is the multi-host shared-pool case,
  # which does not apply here. Flip to false if this pool is ever shared.
  boot.zfs.forceImportRoot = true;
  # These pools hold the mirrored Nix store plus disposable direct-NVMe Steam
  # and developer caches. They import after the HDD root pool at every boot.
  boot.zfs.extraPools = [ "nixpool" "steampool" "devpool" ];
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.generationsDir.copyKernels = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.enable = true;
  # boot.loader.grub.version = 2; # disabled due to deprecation warning
  boot.loader.grub.copyKernels = true;
  boot.loader.grub.efiSupport = true;
  # ┌──────────────────────────────────────────────────────────────────────────┐
  # │ ⛔ NEVER RUN `zpool upgrade bpool`. IT WILL LIKELY MAKE THIS HOST UNBOOTABLE. │
  # └──────────────────────────────────────────────────────────────────────────┘
  # `zfsSupport = true` means GRUB ITSELF reads the pool holding /boot
  # (bpool/nixos/root) to find the kernel and initrd. GRUB's ZFS implementation
  # understands only a SUBSET of ZFS feature flags, so bpool is deliberately
  # created with `compatibility=grub2` and ~20 features left disabled
  # (encryption, large_dnode, sha512, device_removal, log_spacemap, ...).
  #
  # THE TRAP: `zpool status bpool` prints, in ZFS's own words,
  #     status: Some supported and requested features are not enabled on the pool.
  #     action: Enable all features using 'zpool upgrade'.
  # That advice is GENERIC and is WRONG HERE. Following it enables features GRUB
  # cannot parse; GRUB then cannot read /boot, and the machine does not boot.
  # Verify before touching anything: `zpool get compatibility bpool` => grub2.
  #
  # rpool is different: `compatibility=off`, not read by GRUB, so upgrading it is
  # boot-safe -- but still IRREVERSIBLE (an upgraded pool cannot be imported by
  # an older ZFS). Nothing currently needs it. Peter, 2026-08-01.
  boot.loader.grub.zfsSupport = true;
  # Guarded ESP mounts (Peter, 2026-08-01 01:55 EDT).
  #
  # The stock OpenZFS multi-ESP recipe calls `mount` unconditionally here. Linux
  # mounts are a STACK -- mounting over an already-mounted point shadows it
  # rather than erroring -- so every run of this block added one more duplicate.
  # Measured 2026-08-01: 24575 stacked mounts of /boot/efi and 24575 of
  # VCKR0ALP-part1, 49199 mounts total on the machine.
  #
  # The damage is not cosmetic. PID 1 re-parses /proc/self/mountinfo on every
  # mount-table change, so a 49k-entry table starves systemd: nscd, polkit,
  # NetworkManager and systemd-resolved all blew their 90s start timeouts and
  # sat in `activating` indefinitely. It also made mount(8) fail with
  # `move_mount() failed: No space left on device` (a mount-count limit, NOT a
  # full disk -- /boot had 2.4G free) and made general I/O feel sluggish.
  #
  # `mountpoint -q` makes each mount idempotent. Do not remove these guards.
  boot.loader.grub.extraPrepareConfig = ''
    mkdir -p /boot/efis
    for i in /boot/efis/*; do
      ${pkgs.util-linux}/bin/mountpoint -q "$i" || mount "$i"
    done
    mkdir -p /boot/efi
    ${pkgs.util-linux}/bin/mountpoint -q /boot/efi || mount /boot/efi
  '';
  boot.loader.grub.extraInstallCommands = ''
    ESP_MIRROR=$(${pkgs.coreutils}/bin/mktemp -d)
    ${pkgs.coreutils}/bin/cp -r /boot/efi/EFI $ESP_MIRROR
    for i in /boot/efis/*; do
     ${pkgs.coreutils}/bin/cp -r $ESP_MIRROR/EFI $i
    done
    ${pkgs.coreutils}/bin/rm -rf $ESP_MIRROR
  '';
  boot.loader.grub.devices = [
        "/dev/disk/by-id/ata-WDC_WD101FZBX-00ATAA0_VCKR0UGP"
        "/dev/disk/by-id/ata-WDC_WD101FZBX-00ATAA0_VCKR0ALP"
      ];
  # note: set the root user in your main configuration file
  # users.users.root.initialHashedPassword = "$6$xLM1UDNfT/H8lbHK$jKAmqDp39Sj7O.ccOAN4tTBVOL4WoD6RaDcWa/Yg1XFE037sAGsN6WL4psvoKnanybrHYDwSFMWzHcCegp2ht0";
  # users.users.root.hashedPassword = users.users.root.initialHashedPassword;
}
