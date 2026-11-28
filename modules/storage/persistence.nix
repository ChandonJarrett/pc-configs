{
  config,
  inputs,
  lib,
  ...
}:
let
  ephemeral = config.my.storage.root.mode == "ephemeral";
in
{
  imports = [ inputs.preservation.nixosModules.preservation ];

  config = lib.mkIf ephemeral {
    preservation.enable = true;

    # The initrd bind mount already persists machine-id.
    systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

    preservation.preserveAt."/persist" = {
      directories = [
        {
          directory = "/var/lib/nixos";
          inInitrd = true;
        }
        {
          directory = "/var/lib/tailscale";
          mode = "0700";
        }
        {
          directory = "/etc/NetworkManager/system-connections";
          configureParent = true;
          mode = "0700";
        }
        {
          directory = "/var/lib/NetworkManager";
          mode = "0700";
        }
        {
          directory = "/var/log/journal";
          inInitrd = true;
        }
      ]
      ++ lib.optional config.boot.loader.limine.secureBoot.enable "/var/lib/sbctl"
      ++ lib.optional config.hardware.bluetooth.enable {
        directory = "/var/lib/bluetooth";
        mode = "0700";
      }
      ++ lib.optional config.services.fwupd.enable "/var/lib/fwupd"
      ++ lib.optional ((config.hjem.users or { }) != { }) "/var/lib/hjem";

      files = [
        {
          file = "/etc/machine-id";
          inInitrd = true;
        }
      ];
    };
  };
}
