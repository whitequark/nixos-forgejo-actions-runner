{ modulesPath, lib, serverName, siteConfig, ... }:

with lib;

recursiveUpdate {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot = {
    loader.timeout = 15;
    loader.grub.memtest86.enable = true;

    initrd = {
      availableKernelModules = [
        # USB
        "uhci_hcd"
        "ehci_pci"
        "usb_storage"
        "usbhid"
        # (S)ATA
        "ata_piix"
        "ahci"
        "sd_mod"
        # NVMe
        "nvme"
        # Xen
        "xen_blkfront"
      ];
    };

    kernelParams = [
      "zswap.enabled=1"
      "zswap.max_pool_percent=25"
      "zswap.shrinker_enabled=1"
    ];

    tmp.cleanOnBoot = true;
  };

  hardware = {
    enableRedistributableFirmware = true;

    cpu.intel.updateMicrocode =
      (if siteConfig.host ? cpuVendor then siteConfig.host.cpuVendor == "intel" else false);
    cpu.amd.updateMicrocode =
      (if siteConfig.host ? cpuVendor then siteConfig.host.cpuVendor == "amd" else false);
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/root";
    fsType = "ext4";
  };

  swapDevices = (optional (pathExists "/swap") {
    device = "/swap";
    size = 2048;
    options = [ "discard" ];
  }) ++ (optional (pathExists "/dev/disk/by-label/swap") {
    device = "/dev/disk/by-label/swap";
    options = [ "discard" ];
  });

} (if (pathExists /sys/firmware/efi) then {
  # UEFI system
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

} else {
  # BIOS system
  boot.loader.grub.device = (
    head (filter pathExists ["/dev/sda" "/dev/vda"])
  );
})
