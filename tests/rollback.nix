# Exercise rollback failure paths on Btrfs and journal recovery after a hard reset.
{ inputs }:
{
  name = "rollback";
  node.specialArgs = { inherit inputs; };

  nodes.rollback =
    { lib, pkgs, ... }:
    {
      imports = [ ../modules/storage/rollback.nix ];

      my.storage.root = {
        mode = "ephemeral";
        keepDays = 7;
      };

      boot.initrd = {
        kernelModules = [ "btrfs" ];
        supportedFilesystems.btrfs = true;

        systemd = {
          extraBin = {
            blkid = "${pkgs.util-linux}/bin/blkid";
            "mkfs.btrfs" = "${pkgs.btrfs-progs}/bin/mkfs.btrfs";
          };

          services = {
            rollback.requires = lib.mkForce [ "rollback-test-setup.service" ];
            rollback.after = lib.mkForce [ "rollback-test-setup.service" ];

            rollback-test-setup = {
              wantedBy = [ "initrd.target" ];
              before = [ "rollback.service" ];
              requires = [ "dev-disk-by\\x2dlabel-nixos.device" ];
              after = [ "dev-disk-by\\x2dlabel-nixos.device" ];
              unitConfig.DefaultDependencies = false;
              serviceConfig.Type = "oneshot";
              environment.PATH = "/bin:/sbin";
              script = ''
                udevadm settle || true
                for _ in $(seq 1 300); do
                  [ -b /dev/vdb ] && break
                  sleep 0.1
                done

                mkdir -p /dev/mapper
                ln -sf /dev/vdb /dev/mapper/cryptroot

                if ! blkid -p -s TYPE -o value /dev/vdb > /dev/null 2>&1; then
                  mkfs.btrfs -f /dev/vdb
                  mkdir -p /run/rollback-setup
                  mount -t btrfs /dev/vdb /run/rollback-setup
                  btrfs subvolume create /run/rollback-setup/@root
                  printf 'first boot\n' > /run/rollback-setup/@root/marker
                  umount /run/rollback-setup
                fi
              '';
            };
          };
        };
      };

      virtualisation.emptyDiskImages = [ 512 ];

      environment.systemPackages = [ pkgs.btrfs-progs ];

      system.stateVersion = "26.11";
    };

  nodes.persistence =
    { lib, ... }:
    {
      imports = [
        ../modules/storage/persistence.nix
        ../modules/storage/rollback.nix
      ];

      my.storage.root.mode = "ephemeral";

      boot.initrd.systemd.services.rollback.enable = lib.mkForce false;

      services.journald.settings.Journal = {
        Storage = "persistent";
        SystemMaxUse = "1G";
        SyncIntervalSec = "1min";
      };

      virtualisation.emptyDiskImages = [ 512 ];
      virtualisation.fileSystems."/persist" = {
        device = "/dev/vdb";
        fsType = "ext4";
        neededForBoot = true;
        autoFormat = true;
      };

      system.stateVersion = "26.11";
    };

  testScript =
    { nodes, ... }:
    let
      rollbackScript = nodes.rollback.boot.initrd.systemd.services.rollback.script;
    in
    ''
      rollback.start(allow_reboot=True)
      rollback.wait_for_unit("multi-user.target")

      def mount_roots():
          rollback.succeed("mkdir -p /mnt/check")
          rollback.succeed("mount -t btrfs -o subvolid=5 /dev/vdb /mnt/check")

      def unmount_roots():
          rollback.succeed("umount /mnt/check")

      def old_roots():
          return [
              line for line in rollback.succeed(
                  "find /mnt/check/old_roots -mindepth 1 -maxdepth 1 -type d"
              ).splitlines()
              if line
          ]

      with subtest("the first boot moves the seeded @root and creates a fresh one"):
          rollback.succeed("test ! -e /run/rollback-failed")
          mount_roots()
          rollback.succeed("test -d /mnt/check/@root")
          t.assertEqual(len(old_roots()), 1)
          rollback.succeed("test -f /mnt/check/old_roots/*/marker")
          unmount_roots()

      with subtest("a second boot creates a second old root"):
          rollback.reboot()
          rollback.wait_for_unit("multi-user.target")
          mount_roots()
          t.assertEqual(len(old_roots()), 2)
          rollback.succeed('test -z "$(ls -A /mnt/check/@root)"')
          unmount_roots()

      with subtest("old roots are pruned without deleting the newest"):
          mount_roots()
          entries = sorted(old_roots())
          t.assertEqual(len(entries), 2)
          rollback.succeed(f"mv {entries[0]} /mnt/check/old_roots/20000101T000000Z")
          rollback.succeed(f"mv {entries[1]} /mnt/check/old_roots/20000102T175959Z")
          manual_root = "/mnt/check/old_roots/20000101T000000Z-manual"
          rollback.succeed(f"btrfs subvolume create {manual_root}")
          unmount_roots()
          rollback.succeed("ln -sfn /dev/vdb /dev/mapper/cryptroot")
          rollback.succeed(
              "PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin "
              "${rollbackScript}"
          )
          mount_roots()
          entries = old_roots()
          t.assertEqual(len(entries), 2)
          t.assertIn(manual_root, entries)
          t.assertNotIn("/mnt/check/old_roots/20000101T000000Z", entries)
          t.assertNotIn("/mnt/check/old_roots/20000102T175959Z", entries)
          rollback.succeed(f"btrfs subvolume delete {manual_root}")
          rollback.succeed("test -d /mnt/check/@root")
          unmount_roots()

      with subtest("a half-prepared filesystem is recovered on the next boot"):
          mount_roots()
          root = old_roots()[0]
          rollback.succeed(f"mv /mnt/check/@root {root}-interrupted")
          unmount_roots()
          rollback.reboot()
          rollback.wait_for_unit("multi-user.target")
          mount_roots()
          rollback.succeed("test -d /mnt/check/@root")
          rollback.succeed("test -d /mnt/check/old_roots/*-interrupted")
          unmount_roots()

      with subtest("a failed replacement restores the existing root"):
          mount_roots()
          entries = sorted(old_roots())
          rollback.succeed("touch /mnt/check/@root/keep")
          unmount_roots()
          rollback.succeed("ln -sfn /dev/vdb /dev/mapper/cryptroot")
          rollback.succeed(
              "mkdir -p /run/rollback-test/bin && "
              "printf '#!/bin/sh\\nexit 1\\n' > /run/rollback-test/bin/btrfs && "
              "chmod +x /run/rollback-test/bin/btrfs"
          )
          rollback.succeed(
              "PATH=/run/rollback-test/bin:/run/current-system/sw/bin:/run/current-system/sw/sbin "
              "${rollbackScript}"
          )
          rollback.succeed("test -e /run/rollback-failed")
          mount_roots()
          rollback.succeed("test -f /mnt/check/@root/keep")
          t.assertEqual(sorted(old_roots()), entries)
          unmount_roots()
          rollback.succeed("rm /run/rollback-failed")

      with subtest("a failure is marked and the existing root remains available"):
          mount_roots()
          rollback.succeed("mv /mnt/check/old_roots /mnt/check/old_roots.saved")
          rollback.succeed("touch /mnt/check/old_roots")
          unmount_roots()
          rollback.succeed("ln -sfn /dev/vdb /dev/mapper/cryptroot")
          rollback.succeed(
              "PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin "
              "${rollbackScript}"
          )
          rollback.succeed("test -e /run/rollback-failed")
          rollback.fail("systemctl restart rollback-failure-report.service")
          mount_roots()
          rollback.succeed("test -d /mnt/check/@root")
          unmount_roots()

      persistence.start(allow_reboot=True)
      persistence.wait_for_unit("multi-user.target")

      with subtest("preservation mounts the machine id and journal from /persist"):
          persistence.succeed("mountpoint /etc/machine-id")
          persistence.succeed("mountpoint /var/log/journal")
          persistence.succeed("test -d /persist/var/lib/nixos")
          persistence.succeed("test -d /persist/var/lib/tailscale")
          persistence.succeed("grep -Eq '^[0-9a-f]{32}$' /persist/etc/machine-id")
          persistence.succeed("cmp /etc/machine-id /persist/etc/machine-id")
          persistence.succeed("! systemctl is-failed systemd-machine-id-commit.service")
          machine_id = persistence.succeed("cat /etc/machine-id")

      with subtest("the previous boot's journal survives a hard reset"):
          persistence.succeed("logger -t journal-survival 'before hard reset'")
          persistence.succeed("journalctl --sync")
          persistence.crash()
          persistence.start(allow_reboot=True)
          persistence.wait_for_unit("multi-user.target")
          t.assertEqual(persistence.succeed("cat /etc/machine-id"), machine_id)
          journal = persistence.succeed(
              "journalctl -b -1 -t journal-survival --no-pager"
          )
          t.assertIn("before hard reset", journal)
    '';
}
