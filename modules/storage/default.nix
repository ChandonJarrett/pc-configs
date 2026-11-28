{ config, lib, ... }:
let
  storage = import ../../lib/storage.nix;
  ephemeral = config.my.storage.root.mode == "ephemeral";
  mountsSubvolume =
    name: mountpoint:
    let
      mount = config.fileSystems.${mountpoint} or { };
    in
    (mount.device or null) == "/dev/mapper/${storage.luksNames.root}"
    && (mount.fsType or null) == "btrfs"
    && lib.elem "subvol=${name}" (mount.options or [ ]);
in
{
  imports = [
    ./persistence.nix
    ./rollback.nix
  ];

  assertions = [
    {
      assertion = !ephemeral || lib.all lib.id (lib.mapAttrsToList mountsSubvolume storage.subvolumes);
      message = "an ephemeral root requires @root, @nix, @home and @persist on the encrypted Btrfs volume";
    }
  ];

  # Activation needs the password hash and the real home before switching root.
  fileSystems = {
    "/home".neededForBoot = true;
    "/persist".neededForBoot = true;
  };

  boot.tmp = {
    useTmpfs = lib.mkDefault ephemeral;
    tmpfsSize = lib.mkDefault "50%";
  };

  services = {
    fstrim.enable = true;
    btrfs.autoScrub.enable = true;

    journald.settings.Journal = {
      Storage = "persistent";
      SystemMaxUse = "1G";
      SyncIntervalSec = "1min";
    };
  };

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
