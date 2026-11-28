# Compare disko-generated and manual mounts, then check the physical host layouts.
{ inputs, nixosConfigurations }:
let
  inherit (inputs) nixpkgs;
  inherit (nixpkgs) lib;

  storage = import ../lib/storage.nix;

  hostnames = builtins.attrNames nixosConfigurations;

  config = hostname: nixosConfigurations.${hostname}.config;
  laptop = config "lacuna";

  viaDisko = config "meliora";
  samplePartitions = viaDisko.disko.devices.disk.main.content.partitions;
  viaFileSystems =
    (lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        { nixpkgs.hostPlatform = viaDisko.nixpkgs.hostPlatform; }
        ../modules/storage/default.nix
        (storage.mountsFor {
          espUUID = samplePartitions.esp.uuid;
          rootUUID = samplePartitions.root.uuid;
        })
      ];
    }).config;

  partitionsOf = hostname: (config hostname).disko.devices.disk.main.content.partitions;

  hasSwap = hostname: partitionsOf hostname ? cryptswap;
  partitionOf = hostname: name: (partitionsOf hostname).${name};

  partuuidPrefix = "/dev/disk/by-partuuid/";
  bootDevices = lib.concatMap (
    hostname:
    let
      host = config hostname;
    in
    [ host.fileSystems."/boot".device ]
    ++ lib.mapAttrsToList (_: device: device.device) host.boot.initrd.luks.devices
  ) hostnames;
  diskoHosts = lib.filter (hostname: config hostname ? disko) hostnames;

  devices = lib.concatMap (
    hostname: lib.mapAttrsToList (_: fs: fs.device) (config hostname).fileSystems
  ) hostnames;

  stableDevice = device: lib.hasPrefix partuuidPrefix device || lib.hasPrefix "/dev/mapper/" device;

  comparableLuks = devices: lib.mapAttrs (_: device: removeAttrs device [ "preLVM" ]) devices;

  checks = [
    {
      name = "Disko only manages its three dedicated disks";
      ok =
        diskoHosts == [
          "hiraeth"
          "lacuna"
          "meliora"
        ];
    }
    {
      name = "Disko and the manual layout agree on fileSystems";
      ok = viaDisko.fileSystems == viaFileSystems.fileSystems;
    }
    {
      name = "Disko and the manual layout agree on initrd LUKS devices";
      ok =
        comparableLuks viaDisko.boot.initrd.luks.devices
        == comparableLuks viaFileSystems.boot.initrd.luks.devices;
    }
    {
      name = "only the laptop has a 10 GiB encrypted swap partition";
      ok =
        (partitionOf "lacuna" "cryptswap").label == storage.labels.swap
        && (partitionOf "lacuna" "cryptswap").size == "10G"
        && lib.all (hostname: hostname == "lacuna" || !(hasSwap hostname)) diskoHosts;
    }
    {
      name = "the laptop unlocks its swap container in the initrd and swaps to the mapper";
      ok =
        laptop.boot.initrd.luks.devices.cryptswap.device
        == "${partuuidPrefix}${(partitionOf "lacuna" "cryptswap").uuid}"
        && map (swap: swap.device) laptop.swapDevices == [ "/dev/mapper/${storage.luksNames.swap}" ];
    }
    {
      name = "the laptop's disk has a concrete by-id path";
      ok =
        let
          device = laptop.disko.devices.disk.main.device;
        in
        lib.hasPrefix "/dev/disk/by-id/" device && !lib.hasInfix "CHANGE-ME" device;
    }
    {
      name = "only the laptop configures disk swap";
      ok = lib.all (hostname: hostname == "lacuna" || (config hostname).swapDevices == [ ]) hostnames;
    }
    {
      name = "ESP and LUKS devices use unique PARTUUID paths";
      ok =
        lib.all (lib.hasPrefix partuuidPrefix) bootDevices
        && lib.length bootDevices == lib.length (lib.unique bootDevices);
    }
    {
      name = "every mount uses a PARTUUID or a mapper device";
      ok = lib.all stableDevice devices;
    }
    {
      name = "every disko partition carries the documented PARTLABEL";
      ok = lib.all (
        hostname:
        (partitionOf hostname "esp").label == storage.labels.esp
        && (partitionOf hostname "root").label == storage.labels.root
      ) diskoHosts;
    }
    {
      name = "the ESP is EF00 and the LUKS partitions are 8309";
      ok = lib.all (
        hostname:
        (partitionOf hostname "esp").type == "EF00"
        && (partitionOf hostname "root").type == "8309"
        && (!(hasSwap hostname) || (partitionOf hostname "cryptswap").type == "8309")
      ) diskoHosts;
    }
    {
      name = "disko applies each host's PARTUUID";
      ok = lib.all (
        hostname:
        (config hostname).fileSystems."/boot".device
        == "${partuuidPrefix}${(partitionOf hostname "esp").uuid}"
      ) diskoHosts;
    }
    {
      name = "the root partition carries the host's root PARTUUID";
      ok = lib.all (
        hostname:
        (config hostname).boot.initrd.luks.devices.${storage.luksNames.root}.device
        == "${partuuidPrefix}${(partitionOf hostname "root").uuid}"
      ) diskoHosts;
    }
    {
      name = "lacuna keeps swap, ESP and root in partition order";
      ok =
        map (name: (partitionOf "lacuna" name)._index) [
          "cryptswap"
          "esp"
          "root"
        ] == [
          1
          2
          3
        ];
    }
    {
      name = "the disposable LUKS key is absent from physical configurations";
      ok = lib.all (
        hostname:
        let
          initrd = (config hostname).boot.initrd;
        in
        !(initrd.secrets ? "/tmp/secret.key")
        && lib.all (device: device.keyFile != "/tmp/secret.key") (lib.attrValues initrd.luks.devices)
      ) hostnames;
    }
  ];

  failed = builtins.filter (check: !check.ok) checks;
in
if failed == [ ] then
  "storage: ok"
else
  throw "storage checks failed: ${lib.concatMapStringsSep ", " (check: check.name) failed}"
