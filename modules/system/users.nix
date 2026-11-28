{
  constants,
  lib,
  pkgs,
  ...
}:
let
  user = constants.username;
in
{
  users = {
    # The declarative hash is the only source of truth. The console, the greeter, and sudo
    # all read /etc/shadow, which every fresh root rebuilds from it.
    mutableUsers = false;

    users.${user} = {
      isNormalUser = true;
      extraGroups = [
        "networkmanager"
        "wheel"
      ];

      # The installer places this root-owned 0400 file on encrypted storage.
      hashedPasswordFile = lib.mkDefault "/persist/secrets/shadow-hash";
    };
  };

  security.sudo.wheelNeedsPassword = lib.mkDefault true;

  # A missing or unreadable hash is a silent lockout: nixpkgs only warns, and the machine
  # boots to a greeter nobody can pass.
  systemd.services.password-hash-check = {
    wantedBy = [ "multi-user.target" ];

    serviceConfig.Type = "oneshot";

    script = ''
      hash="$(${pkgs.gnugrep}/bin/grep -E '^${user}:' /etc/shadow | ${pkgs.coreutils}/bin/cut -d: -f2)"
      case "$hash" in
        "" | "!"* | "*"*)
          ${pkgs.util-linux}/bin/wall "${user} has no usable password hash"
          echo "no password hash for ${user} in /etc/shadow" >&2
          exit 1
          ;;
      esac
    '';
  };
}
