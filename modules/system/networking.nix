{ lib, ... }:
{
  networking = {
    firewall.enable = true;
    networkmanager.enable = true;
  };

  services.tailscale = {
    enable = true;
    extraSetFlags = lib.mkDefault [ "--ssh=false" ];
  };
}
