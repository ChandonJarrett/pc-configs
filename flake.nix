{
  description = "Declarative NixOS configurations for multiple personal machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    preservation.url = "github:nix-community/preservation";

    hjem = {
      url = "github:feel-co/hjem";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, ... }@inputs:
    let
      inherit (nixpkgs) lib;
      system = "x86_64-linux";
      constants = import ./lib/constants.nix;

      hosts = [
        "forlorn"
        "meliora"
        "lacuna"
        "hiraeth"
      ];

      pkgs = nixpkgs.legacyPackages.${system};

      mkHost =
        hostname:
        lib.nixosSystem {
          specialArgs = { inherit constants inputs; };
          modules = [
            {
              networking.hostName = hostname;
              nixpkgs.hostPlatform = system;
            }
            ./hosts/${hostname}
          ];
        };
      nixosConfigurations = lib.genAttrs hosts mkHost;
      diskoHosts = lib.filterAttrs (_: host: host.config ? disko) nixosConfigurations;
    in
    {
      inherit nixosConfigurations;

      checks.${system} = {
        options = pkgs.writeText "host-options" (
          import ./tests/options.nix {
            inherit inputs nixosConfigurations;
          }
          + "\n"
        );
        storage = pkgs.writeText "host-storage" (
          import ./tests/storage.nix {
            inherit inputs nixosConfigurations;
          }
          + "\n"
        );
        login = pkgs.testers.runNixOSTest (import ./tests/login.nix { inherit inputs; });
        rollback = pkgs.testers.runNixOSTest (import ./tests/rollback.nix { inherit inputs; });
        encrypted-boot = import ./tests/encrypted-boot.nix {
          inherit inputs pkgs;
          host = nixosConfigurations.lacuna;
        };
      }
      // lib.mapAttrs' (
        hostname: host: lib.nameValuePair "system-${hostname}" host.config.system.build.toplevel
      ) nixosConfigurations
      // lib.mapAttrs' (
        hostname: host:
        lib.nameValuePair "disk-image-${hostname}" host.config.virtualisation.vmVariantWithDisko.system.build.diskoImages
      ) diskoHosts;

      formatter.${system} = pkgs.nixfmt-tree;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.deadnix
          inputs.disko.packages.${system}.disko
          pkgs.git
          pkgs.gitleaks
          pkgs.nix
          pkgs.nixfmt-tree
          pkgs.statix
        ];

        shellHook = ''
          if git rev-parse --is-inside-work-tree >/dev/null 2>&1 && ! git config --get core.hooksPath >/dev/null; then
            git config --local core.hooksPath .githooks
          fi
        '';
      };
    };
}
