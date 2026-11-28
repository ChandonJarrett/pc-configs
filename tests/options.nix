# Evaluate policy against the same locked graph as the build checks.
{ inputs, nixosConfigurations }:
let
  inherit (inputs.nixpkgs) lib;

  constants = import ../lib/constants.nix;

  hostnames = builtins.attrNames nixosConfigurations;

  config = hostname: nixosConfigurations.${hostname}.config;

  user = constants.username;

  userConfig = hostname: (config hostname).users.users.${user};

  trustedUsers = hostname: (config hostname).nix.settings.trusted-users or [ ];

  nonRootTrusted = lib.filter (user: user != "root") (
    lib.concatMap (hostname: lib.toList (trustedUsers hostname)) hostnames
  );

  checks = [
    {
      name = "no non-root trusted user is configured";
      ok = nonRootTrusted == [ ];
    }
    {
      name = "the build directory is /nix/var/nix/builds";
      ok = lib.all (
        hostname: (config hostname).nix.settings.build-dir == "/nix/var/nix/builds"
      ) hostnames;
    }
    {
      name = "the journal is persistent and bounded";
      ok = lib.all (
        hostname:
        let
          journal = (config hostname).services.journald.settings.Journal;
        in
        journal.Storage == "persistent" && journal.SystemMaxUse == "1G"
      ) hostnames;
    }
    {
      name = "zram, TRIM and scrub are enabled everywhere";
      ok = lib.all (
        hostname:
        (config hostname).zramSwap.enable
        && (config hostname).services.fstrim.enable
        && (config hostname).services.btrfs.autoScrub.enable
      ) hostnames;
    }
    {
      name = "Limine keeps three generations and no editor";
      ok = lib.all (
        hostname:
        let
          limine = (config hostname).boot.loader.limine;
        in
        limine.enable && limine.efiSupport && limine.maxGenerations == 3 && !limine.enableEditor
      ) hostnames;
    }
    {
      name = "redistributable firmware is available on every host";
      ok = lib.all (hostname: (config hostname).hardware.enableRedistributableFirmware) hostnames;
    }
    {
      name = "the experimental features the flake needs are enabled";
      ok = lib.all (
        hostname:
        let
          features = (config hostname).nix.settings.experimental-features or [ ];
        in
        lib.elem "nix-command" features && lib.elem "flakes" features
      ) hostnames;
    }
    {
      name = "Bluetooth is enabled on every host";
      ok = lib.all (hostname: (config hostname).hardware.bluetooth.enable) hostnames;
    }
    {
      name = "every host states the memory watchdog and the laptop takes firmware updates";
      ok =
        lib.all (hostname: (config hostname).systemd.oomd.enable) hostnames
        && (config "lacuna").services.fwupd.enable;
    }
    {
      name = "the laptop gives /tmp a quarter of RAM and the other hosts a half";
      ok = lib.all (
        hostname: (config hostname).boot.tmp.tmpfsSize == (if hostname == "lacuna" then "25%" else "50%")
      ) hostnames;
    }
    {
      name = "/home and /persist are available to activation on every host";
      ok = lib.all (
        hostname:
        let
          fs = (config hostname).fileSystems;
        in
        fs."/home".neededForBoot && fs."/persist".neededForBoot
      ) hostnames;
    }
    {
      name = "ephemeral hosts run rollback while the server keeps a persistent root";
      ok = lib.all (
        hostname:
        let
          host = config hostname;
          ephemeral = host.my.storage.root.mode == "ephemeral";
        in
        ephemeral == (hostname != "hiraeth")
        && host.my.storage.root.keepDays == 7
        && host.preservation.enable == ephemeral
        && lib.elem "systemd-machine-id-commit.service" host.systemd.suppressedSystemUnits == ephemeral
        && (host.boot.initrd.systemd.services ? rollback) == ephemeral
        && (builtins.hasAttr "rollback-failure-report" host.systemd.services) == ephemeral
      ) hostnames;
    }
    {
      name = "rollback is ordered before sysroot and pulls in cryptsetup";
      ok = lib.all (
        hostname:
        let
          unit = (config hostname).boot.initrd.systemd.services.rollback;
        in
        (config hostname).my.storage.root.mode == "persistent"
        || (
          lib.elem "sysroot.mount" unit.before
          && lib.elem "systemd-cryptsetup@cryptroot.service" unit.requires
          && lib.elem "systemd-hibernate-resume.service" unit.after
          && unit.unitConfig.DefaultDependencies == false
        )
      ) hostnames;
    }
    {
      name = "preservation maps the declared directories and files";
      ok = lib.all (
        hostname:
        let
          host = config hostname;
          state = host.preservation.preserveAt;
          dirs = state."/persist".directories or [ ];
          files = state."/persist".files or [ ];
          directory = path: lib.findFirst (entry: entry.directory == path) { } dirs;
        in
        if host.my.storage.root.mode == "persistent" then
          state == { }
        else
          ((directory "/var/lib/nixos").inInitrd or false)
          && ((directory "/var/log/journal").inInitrd or false)
          && lib.all (path: ((directory path).mode or null) == "0700") [
            "/var/lib/tailscale"
            "/var/lib/NetworkManager"
            "/etc/NetworkManager/system-connections"
          ]
          && (!host.hardware.bluetooth.enable || ((directory "/var/lib/bluetooth").mode or null) == "0700")
          && (!host.services.fwupd.enable || lib.any (entry: entry.directory == "/var/lib/fwupd") dirs)
          && lib.any (entry: entry.file == "/etc/machine-id" && entry.inInitrd) files
      ) hostnames;
    }
    {
      name = "/tmp is tmpfs on every ephemeral host and on disk on the server";
      ok = lib.all (
        hostname:
        (config hostname).boot.tmp.useTmpfs == ((config hostname).my.storage.root.mode == "ephemeral")
      ) hostnames;
    }
    {
      name = "the single user is in wheel and passwords are declarative";
      ok = lib.all (
        hostname:
        let
          inherit ((config hostname)) users;
        in
        !users.mutableUsers && lib.elem "wheel" users.users.${user}.extraGroups
      ) hostnames;
    }
    {
      name = "no plaintext password is configured";
      ok = lib.all (hostname: (userConfig hostname).password == null) hostnames;
    }
    {
      name = "hjem manages the user's home";
      ok = lib.all (hostname: (config hostname).hjem.users.${user}.user == user) hostnames;
    }
    {
      name = "Tailscale runs on every host without OpenSSH";
      ok = lib.all (
        hostname:
        let
          host = config hostname;
        in
        host.services.tailscale.enable && !host.services.openssh.enable
      ) hostnames;
    }
    {
      name = "GitHub SSH uses the local agent and only the server has passwordless sudo";
      ok = lib.all (
        hostname:
        let
          host = config hostname;
        in
        host.programs.ssh.startAgent
        && host.programs.ssh.hosts."github.com".IdentitiesOnly
        && host.security.sudo.wheelNeedsPassword == (hostname != "hiraeth")
      ) hostnames;
    }
    {
      name = "Tailscale SSH is enabled only on hiraeth";
      ok = lib.all (
        hostname:
        (config hostname).services.tailscale.extraSetFlags
        == [ (if hostname == "hiraeth" then "--ssh" else "--ssh=false") ]
      ) hostnames;
    }
    {
      name = "the password hash file sits on encrypted persistent storage";
      ok = lib.all (
        hostname:
        (userConfig hostname).hashedPasswordFile == (
          if hostname == "hiraeth" then "/var/lib/secrets/shadow-hash" else "/persist/secrets/shadow-hash"
        )
      ) hostnames;
    }
  ];

  failed = builtins.filter (check: !check.ok) checks;

in
if failed == [ ] then
  "options: ok"
else
  throw "option checks failed: ${lib.concatMapStringsSep ", " (check: check.name) failed}"
