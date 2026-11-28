{ lib, ... }:
{
  imports = [
    ../modules/boot.nix
    ../modules/storage/default.nix
    ../modules/system/hjem.nix
    ../modules/system/networking.nix
    ../modules/system/nix.nix
    ../modules/system/ssh.nix
    ../modules/system/users.nix
  ];

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "America/New_York";
  console.keyMap = "us";

  # On by default upstream; stated so a default change cannot silently drop the memory
  # watchdog. enableRootSlice stays off, so system services are never the first victim.
  systemd.oomd.enable = true;

  # Default to both microcode sets for hosts without a hardware module.
  hardware = {
    enableRedistributableFirmware = true;
    cpu.intel.updateMicrocode = lib.mkDefault true;
    cpu.amd.updateMicrocode = lib.mkDefault true;

    bluetooth.enable = true;
  };
}
