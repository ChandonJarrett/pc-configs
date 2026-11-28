_: {
  boot.loader = {
    efi.canTouchEfiVariables = true;

    limine = {
      enable = true;
      efiSupport = true;

      # Limine copies each retained generation's kernel and initrd onto the 1 GiB ESP
      # (~100 MiB per generation); three leaves most of it free for the binary and config.
      maxGenerations = 3;

      # The editor allows init=/bin/sh, which would bypass the login password.
      enableEditor = false;
    };
  };
}
