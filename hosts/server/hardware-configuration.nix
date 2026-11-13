# Placeholder hardware configuration for server
# This will be replaced during installation with the real hardware config
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # Dell OptiPlex 7060 - Intel i5-8500
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Placeholder - will be populated after installation
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/PLACEHOLDER";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/PLACEHOLDER";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/PLACEHOLDER"; }
  ];

  # Additional media drive will be added here after installation
  # fileSystems."/mnt/media" = {
  #   device = "/dev/disk/by-uuid/MEDIA-DRIVE-UUID";
  #   fsType = "ext4";
  # };

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
