{ config, pkgs, ... }:

{ boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "a3e8353c";
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.generationsDir.copyKernels = true;
  boot.loader.grub.efiInstallAsRemovable = true;
  boot.loader.grub.enable = true;
  # boot.loader.grub.version = 2; # disabled due to deprecation warning
  boot.loader.grub.copyKernels = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.zfsSupport = true;
  boot.loader.grub.extraPrepareConfig = ''
    mkdir -p /boot/efis
    for i in  /boot/efis/*; do mount $i ; done
    mkdir -p /boot/efi
    mount /boot/efi
  '';
  boot.loader.grub.extraInstallCommands = ''
  ESP_MIRROR=$(mktemp -d)
  cp -r /boot/efi/EFI $ESP_MIRROR
  for i in /boot/efis/*; do
  cp -r $ESP_MIRROR/EFI $i
  done
  rm -rf $ESP_MIRROR
  '';
  boot.loader.grub.devices = [
        "/dev/disk/by-id/ata-WDC_WD101FZBX-00ATAA0_VCKR0UGP"
        "/dev/disk/by-id/ata-WDC_WD101FZBX-00ATAA0_VCKR0ALP"
      ];
  # note: set the root user in your main configuration file
  # users.users.root.initialHashedPassword = "$6$xLM1UDNfT/H8lbHK$jKAmqDp39Sj7O.ccOAN4tTBVOL4WoD6RaDcWa/Yg1XFE037sAGsN6WL4psvoKnanybrHYDwSFMWzHcCegp2ht0";
  # users.users.root.hashedPassword = users.users.root.initialHashedPassword;
}
