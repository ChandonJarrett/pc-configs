# Shared layout for disko-managed disks and the manually partitioned host.
rec {
  labels = {
    esp = "nixos-esp";
    swap = "nixos-swap";
    root = "nixos-root";
  };

  luksNames = {
    root = "cryptroot";
    swap = "cryptswap";
  };

  espSize = "1G";
  espMountOptions = [ "umask=0077" ];

  btrfsMountOptions = [
    "compress=zstd:1"
    "noatime"
  ];
  btrfsExtraArgs = [
    "-m"
    "dup"
    "-d"
    "single"
  ];

  subvolumes = {
    "@root" = "/";
    "@nix" = "/nix";
    "@home" = "/home";
    "@persist" = "/persist";
  };

  diskFor =
    {
      device,
      espUUID,
      rootUUID,
      swap ? null,
    }:
    let
      swapPartition = {
        cryptswap = {
          inherit (swap) size uuid;
          # Keep swap at partition 1 on lacuna.
          priority = 100;
          type = "8309";
          label = labels.swap;
          content = {
            type = "luks";
            name = luksNames.swap;
            settings.allowDiscards = true;
            content.type = "swap";
          };
        };
      };
    in
    {
      type = "disk";
      inherit device;
      content = {
        type = "gpt";
        partitions = {
          esp = {
            type = "EF00";
            size = espSize;
            label = labels.esp;
            uuid = espUUID;
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = espMountOptions;
            };
          };
          root = {
            size = "100%";
            type = "8309";
            label = labels.root;
            uuid = rootUUID;
            content = {
              type = "luks";
              name = luksNames.root;
              settings.allowDiscards = true;
              content = {
                type = "btrfs";
                extraArgs = btrfsExtraArgs;
                subvolumes = builtins.mapAttrs (_: mountpoint: {
                  inherit mountpoint;
                  mountOptions = btrfsMountOptions;
                }) subvolumes;
              };
            };
          };
        }
        // (if swap != null then swapPartition else { });
      };
    };

  mountsFor =
    { espUUID, rootUUID }:
    {
      fileSystems = {
        "/boot" = {
          device = "/dev/disk/by-partuuid/${espUUID}";
          fsType = "vfat";
          options = espMountOptions;
        };
      }
      // builtins.listToAttrs (
        map (subvolume: {
          name = subvolumes.${subvolume};
          value = {
            device = "/dev/mapper/${luksNames.root}";
            fsType = "btrfs";
            options = btrfsMountOptions ++ [ "subvol=${subvolume}" ];
          };
        }) (builtins.attrNames subvolumes)
      );

      boot.initrd.luks.devices.${luksNames.root} = {
        device = "/dev/disk/by-partuuid/${rootUUID}";
        allowDiscards = true;
      };
    };
}
