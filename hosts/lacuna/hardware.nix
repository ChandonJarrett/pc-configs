{ config, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "nvme"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  hardware.cpu = {
    intel.updateMicrocode = config.hardware.enableRedistributableFirmware;
    amd.updateMicrocode = false;
  };
}
