_: {
  nix = {
    settings = {
      # Rewriting hard links at the end of every build costs more than the nightly timer
      # below, which does the same work off the critical path.
      auto-optimise-store = false;

      # Never /tmp (tmpfs on the ephemeral hosts) and never /var/tmp (world-writable).
      build-dir = "/nix/var/nix/builds";

      # The repository is a flake and every check command is a flake command, so a
      # machine without these cannot be rebuilt from its own configuration.
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };

    # Both timers are non-persistent: /var/lib/systemd/timers is not preserved.
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
      persistent = false;
    };

    optimise = {
      automatic = true;
      dates = [ "03:45" ];
      persistent = false;
    };
  };
}
