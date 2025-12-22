{ modulesPath, lib, ... }:

with lib;

recursiveUpdate {
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/root";
    fsType = "ext4";
  };

  boot = {
    initrd = {
      availableKernelModules = [ "ata_piix" "uhci_hcd" "xen_blkfront" ];
      kernelModules = [ "nvme" ];
    };

    loader.timeout = 15;
    tmp.cleanOnBoot = true;
  };

  swapDevices = (optional (pathExists "/swap") {
    device = "/swap";
    size = 2048;
  });
  zramSwap.enable = true;

} (if (pathExists /sys/firmware/efi) then {
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
  };

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

} else {
  boot.loader.grub.device = (
    head (filter pathExists ["/dev/sda" "/dev/vda"])
  );
})
