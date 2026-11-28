{
  imports = [
    ../../profiles/base.nix
    ../../modules/storage/disko.nix
  ];

  disko.devices.disk.main = (import ../../lib/storage.nix).diskFor {
    device = "/dev/disk/by-id/CHANGE-ME";
    espUUID = "0ac44b8b-2ee4-4b90-a375-4dce0f442f97";
    rootUUID = "0077dee1-08b7-4193-a9dd-f910e7bf3c76";
  };

  system.stateVersion = "26.11";
}
