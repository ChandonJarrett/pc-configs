{ constants, ... }:
{
  imports = [
    ../../profiles/base.nix
    ../../modules/storage/disko.nix
  ];

  disko.devices.disk.main = (import ../../lib/storage.nix).diskFor {
    device = "/dev/disk/by-id/CHANGE-ME";
    espUUID = "fab1e4f5-f09e-41e6-a5f2-f1703df5bb8b";
    rootUUID = "1c274884-cd91-4272-baf2-02ac7a3ea340";
  };

  my.storage.root.mode = "persistent";

  services.tailscale.extraSetFlags = [ "--ssh" ];

  users.users.${constants.username}.hashedPasswordFile = "/var/lib/secrets/shadow-hash";
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "26.11";
}
