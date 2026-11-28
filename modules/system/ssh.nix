{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.git ];

  programs.ssh = {
    startAgent = true;

    hosts."github.com" = {
      order = 100;
      User = "git";
      IdentityFile = "~/.ssh/id_ed25519_github";
      IdentitiesOnly = true;
      AddKeysToAgent = "1h";
      ServerAliveInterval = 15;
    };
  };

  # Only hiraeth accepts inbound SSH, through Tailscale.
  services.openssh.enable = false;
}
