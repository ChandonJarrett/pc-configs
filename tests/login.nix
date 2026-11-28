{ inputs }:
let
  constants = import ../lib/constants.nix;
  user = constants.username;

  # A throwaway hash for the password `vm`. Unlike a host, the test reads it straight from
  # the store, which is fine for a credential that protects nothing.
  passwordHash = ./fixtures/password-hash;
in
{
  name = "login";

  node.specialArgs = { inherit constants inputs; };

  # The modules the hosts use, with the hash file overridden so the VM needs no /persist.
  nodes.machine =
    { lib, ... }:
    {
      imports = [
        ../modules/system/hjem.nix
        ../modules/system/ssh.nix
        ../modules/system/users.nix
      ];

      users.users.${user}.hashedPasswordFile = lib.mkForce "${passwordHash}";

      system.stateVersion = "26.11";
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("the hash file is the user's shadow entry"):
        machine.succeed(
            "cut -d: -f1,2 /etc/shadow | grep -qxF "
            "\"${user}:$(cat ${passwordHash})\""
        )
        machine.succeed(
            "systemctl show -p Result --value password-hash-check.service | grep -qx success"
        )

    with subtest("the console accepts the password from the fixture"):
        machine.wait_until_succeeds("pgrep -f 'agetty.*tty1'")
        machine.wait_until_tty_matches("1", "login: ")
        machine.send_chars("${user}\n")
        machine.wait_until_tty_matches("1", "Password: ")
        machine.send_chars("vm\n")
        machine.wait_until_succeeds("pgrep -u ${user} bash")

    with subtest("GitHub uses a dedicated identity and the login starts an SSH agent"):
        options = machine.succeed("ssh -G github.com 2>/dev/null").splitlines()
        t.assertIn("user git", options)
        t.assertIn("identityfile ~/.ssh/id_ed25519_github", options)
        t.assertIn("identitiesonly yes", options)
        t.assertIn("forwardagent no", options)
        machine.wait_until_succeeds("test -S /run/user/$(id -u ${user})/ssh-agent")
  '';
}
