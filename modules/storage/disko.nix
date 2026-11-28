{
  config,
  inputs,
  lib,
  ...
}:
let
  storage = import ../../lib/storage.nix;
  inherit (storage) luksNames;
in
{
  imports = [ inputs.disko.nixosModules.disko ];

  disko.tests.efi = true;

  virtualisation.vmVariantWithDisko = {
    virtualisation = {
      graphics = false;

      fileSystems."/home".neededForBoot = true;
    };

    disko.devices.disk.main.imageSize = "24G";

    boot = {
      # EFI variables from the image builder do not carry over.
      loader.efi.canTouchEfiVariables = lib.mkForce false;

      initrd.luks.devices = {
        ${luksNames.root}.keyFile = "/tmp/secret.key";
      }
      // lib.optionalAttrs (config.disko.devices.disk.main.content.partitions ? cryptswap) {
        ${luksNames.swap}.keyFile = "/tmp/secret.key";
      };
      initrd.secrets."/tmp/secret.key" = builtins.toFile "secret.key" "disko";
    };
  };
}
