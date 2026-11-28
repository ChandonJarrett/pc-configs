{
  inputs,
  pkgs,
  host,
}:
let
  inherit (import ../lib/constants.nix) username;
  inherit (import ../lib/storage.nix) luksNames;
  hash = ./fixtures/password-hash;
  key = "/tmp/secret.key";
  uid = "1234";
  testLuks = {
    passwordFile = key;
    # Keep the two disposable LUKS unlocks cheap under software emulation.
    extraFormatArgs = [
      "--pbkdf"
      "pbkdf2"
      "--pbkdf-force-iterations"
      "1000"
    ];
  };
  testHost = host.extendModules {
    modules = [
      {
        disko.devices.disk.main.content.partitions = {
          root.content = testLuks;
          cryptswap.content = testLuks;
        };
      }
    ];
  };
in
inputs.disko.lib.testLib.makeDiskoTest {
  name = "lacuna-encrypted-boot";
  inherit pkgs;
  inherit (testHost) extendModules;
  disko-config = testHost.config;
  testMode = "direct";
  efi = true;

  extraInstallerConfig.virtualisation.emptyDiskImages = pkgs.lib.mkForce [ 24576 ];

  extraSystemConfig = {
    boot = {
      loader.efi.canTouchEfiVariables = pkgs.lib.mkForce false;
      initrd.luks.devices = {
        ${luksNames.root}.keyFile = key;
        ${luksNames.swap}.keyFile = key;
      };
      initrd.secrets.${key} = pkgs.writeText "disko-test-key" "secretsecret";
    };
  };

  postDisko = ''
    machine.succeed("install -D -m 0400 ${hash} /mnt/persist/secrets/shadow-hash")
    machine.succeed("mkdir -p /mnt/persist/var/lib/nixos")
    machine.succeed("""echo '{"${username}":${uid}}' > /mnt/persist/var/lib/nixos/uid-map""")
    installer = machine
  '';

  extraTestScript = ''
    def check_boot():
        machine.wait_for_unit("multi-user.target")
        machine.succeed("test -d /sys/firmware/efi")
        machine.succeed("test -f /boot/efi/boot/BOOTX64.EFI")
        machine.succeed("grep -qi 'protocol.*linux' /boot/limine/limine.conf")
        machine.succeed("cryptsetup status ${luksNames.root}")
        machine.succeed("lsblk -no MOUNTPOINT /dev/mapper/${luksNames.swap} | grep -Fx '[SWAP]'")
        machine.succeed("findmnt -no FSROOT /home | grep -Fx /@home")
        machine.succeed("stat -c '%u:%a' /home/${username} | grep -Fx ${uid}:700")
        machine.succeed("cmp /etc/machine-id /persist/etc/machine-id")
        machine.succeed("grep -Eq '^[0-9a-f]{32}$' /etc/machine-id")
        machine.succeed("test ! -e /run/rollback-failed")
        machine.succeed("! systemctl is-failed systemd-machine-id-commit.service")

    check_boot()
    machine.wait_until_tty_matches("1", "login: ")
    machine.send_chars("${username}\n")
    machine.wait_until_tty_matches("1", "Password: ")
    machine.send_chars("vm\n")
    machine.wait_until_succeeds("pgrep -u ${username} bash")
    machine_id = machine.succeed("cat /etc/machine-id")
    machine.succeed("touch /root/boot-test /home/${username}/boot-test")
    machine.succeed("logger -t encrypted-boot before-reboot && journalctl --sync")
    machine.shutdown()

    machine = create_test_machine(oldmachine=installer, name="rebooted_machine")
    machine.start()
    check_boot()
    machine.succeed("test ! -e /root/boot-test && test -f /home/${username}/boot-test")
    machine.succeed("journalctl -b -1 -t encrypted-boot | grep -F before-reboot")
    t.assertEqual(machine.succeed("cat /etc/machine-id"), machine_id)
  '';
}
