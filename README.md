# PC configs

Four x86_64 NixOS machines with UEFI, Limine, and encrypted Btrfs.

| Host | Disk layout | Root |
| --- | --- | --- |
| `lacuna` | Disko on the laptop's NVMe, with 10 GiB of encrypted swap | Recreated at boot |
| `forlorn` | Manual Linux partitions in free space on the Windows disk | Recreated at boot |
| `meliora` | Disko on a separate Linux disk. Hardware and disk identity pending. | Recreated at boot |
| `hiraeth` | Disko on the server disk. Hardware and disk identity pending. | Persistent |

Each host's entry in [hosts/](hosts/) imports the [base profile](profiles/base.nix) and declares its disk identities and overrides. The [storage layout](lib/storage.nix) is shared. Add detected hardware settings with `nixos-generate-config --no-filesystems` and import the file from the matching host. Keep an installed host's `system.stateVersion` at its install value.

## Develop and rebuild

```sh
nix develop
nix fmt
nix flake check --no-build
nix flake check -L
sudo nixos-rebuild boot --flake .#lacuna
```

Use `switch` to apply a generation immediately. `boot` selects it for the next reboot. Limine retains three generations. Add new Nix files to Git before evaluating a Git-backed checkout.

The development shell sets up the Git hooks when no hooks path is configured. Pre-commit checks formatting and lint in the working tree and scans staged changes for secrets. Pre-push runs the full flake check for each outgoing revision. The checks build the host systems and disposable Disko images and cover console login, root recreation, journal survival, and encrypted EFI boot.

## Install and recover

Disko formats the entire selected disk. On `lacuna`, match the host's by-id path to the physical device before using `nix develop --command disko --mode disko --flake .#lacuna` from a live installer. For `forlorn`, create the Linux partitions manually in existing free space and preserve the Windows partitions and Windows ESP. Check the real disk identity and hardware before attempting either pending Disko install.

With the target mounted under `/mnt`, provision a nonempty login hash before running `nixos-install`. Generate it with `mkpasswd -m yescrypt`. Store it as root with mode `0400` at `/mnt/persist/secrets/shadow-hash`, or at `/mnt/var/lib/secrets/shadow-hash` on `hiraeth`. Keep the hash outside Git and the Nix store.

For recovery, boot a live installer and identify the existing Linux partitions by the host's PARTUUIDs. Unlock the root partition as `cryptroot`. Mount `@root` at `/mnt`, then mount `@nix`, `@home`, `@persist`, and the Linux ESP at the matching paths under `/mnt`. If `@root` is missing, inspect Btrfs subvolume ID 5 and restore the intended archive from `old_roots/`. Use `nixos-enter --root /mnt` to inspect the mounted system. Recovery of an existing installation uses those mounts without formatting them.

## Accounts and network

NetworkManager profiles, machine identity, and system logs live under `/persist` on ephemeral hosts. `hiraeth` uses Tailscale SSH, subject to tailnet policy. Verify local recovery and an unattended encrypted reboot before relying on it remotely.

GitHub SSH uses a per-machine key at `~/.ssh/id_ed25519_github` and the OpenSSH agent. Add the public key in GitHub and verify with `ssh -T git@github.com`. [GitHub key setup](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account)
