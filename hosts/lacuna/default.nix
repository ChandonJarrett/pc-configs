{
  imports = [
    ./hardware.nix
    ../../profiles/base.nix
    ../../modules/storage/disko.nix
  ];

  disko.devices.disk.main = (import ../../lib/storage.nix).diskFor {
    device = "/dev/disk/by-id/nvme-SAMSUNG_MZAL4256HBJD-00BL1_S67RNF0W187255";
    espUUID = "974f9094-df46-450c-aec3-673e969bf3ec";
    rootUUID = "42478bf2-d29a-40fd-b9ff-064429136ba8";
    swap = {
      size = "10G";
      uuid = "0f4b7c21-58ad-4d1e-9a63-7c2e5b04d891";
    };
  };

  services.fwupd.enable = true;

  boot.tmp.tmpfsSize = "25%";

  system.stateVersion = "26.11";
}
