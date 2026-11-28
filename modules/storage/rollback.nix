{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.storage.root;

  inherit (import ../../lib/storage.nix) luksNames;
  cryptsetupUnit = "systemd-cryptsetup@${luksNames.root}.service";
  mapper = "/dev/mapper/${luksNames.root}";

  rollback = pkgs.writeShellScript "rollback" ''
    set -u
    export LC_ALL=C

    device=${lib.escapeShellArg mapper}
    mountpoint=/run/rollback
    marker=/run/rollback-failed
    archive="$mountpoint/old_roots"
    root="$mountpoint/@root"
    keep_days=${toString cfg.keepDays}
    mounted=
    target=

    log() {
      message="rollback: $*"
      printf '%s\n' "$message" >&2
      printf '%s\n' "$message" > /dev/kmsg || true
      printf '%s\n' "$message" > /dev/console || true
    }

    fail() {
      : > "$marker"
      log "$*"
    }

    cleanup() {
      if [ -n "$mounted" ]; then
        umount "$mountpoint" || fail "could not unmount $mountpoint"
      fi
      rmdir "$mountpoint" 2>/dev/null || true
      exit 0
    }

    trap cleanup EXIT

    mkdir -p "$mountpoint" || {
      fail "could not create $mountpoint"
      exit 0
    }

    if ! mount -t btrfs -o subvolid=5 "$device" "$mountpoint"; then
      fail "could not mount the top-level Btrfs filesystem"
      exit 0
    fi
    mounted=1

    if [ -d "$root" ]; then
      if [ -L "$archive" ] || ! mkdir -p "$archive"; then
        fail "could not prepare old_roots"
        exit 0
      fi

      # Rename atomically and keep archives distinct if two boots share a timestamp.
      timestamp="$(date -u +%Y%m%dT%H%M%SZ)" || {
        fail "could not read the clock"
        exit 0
      }
      target="$archive/$timestamp"
      suffix=1
      while [ -e "$target" ] || [ -L "$target" ]; do
        target="$archive/$timestamp-$suffix"
        suffix=$((suffix + 1))
      done

      if mv -T "$root" "$target"; then
        log "moved @root to old_roots/''${target##*/}"
      else
        fail "could not archive @root"
        exit 0
      fi
    fi

    if btrfs subvolume create "$root" > /dev/null; then
      log "created @root"
    else
      fail "could not create @root"
      if [ -n "$target" ] && [ ! -e "$root" ] && [ ! -L "$root" ]; then
        if mv -T "$target" "$root"; then
          log "restored the previous @root"
        else
          fail "could not restore @root from old_roots/''${target##*/}"
        fi
      fi
      exit 0
    fi

    [ -d "$archive" ] && [ ! -L "$archive" ] || exit 0
    now="$(date -u +%s)" || {
      fail "could not read the clock"
      exit 0
    }
    cutoff=$((now - keep_days * 86400))

    newest=
    newest_epoch=0
    newest_suffix=0
    expired=()
    for entry in "$archive"/*; do
      [ -d "$entry" ] && [ ! -L "$entry" ] || continue
      name="''${entry##*/}"
      [[ "$name" =~ ^([0-9]{8}T[0-9]{6}Z)(-([1-9][0-9]*))?$ ]] || continue
      stamp="''${BASH_REMATCH[1]}"
      suffix="''${BASH_REMATCH[3]:-0}"
      stamp_epoch="$(date -u -d "''${stamp:0:4}-''${stamp:4:2}-''${stamp:6:2} ''${stamp:9:2}:''${stamp:11:2}:''${stamp:13:2}Z" +%s 2>/dev/null)" || continue

      if [ -z "$newest" ] || (( stamp_epoch > newest_epoch ||
        (stamp_epoch == newest_epoch && suffix > newest_suffix) )); then
        newest="$entry"
        newest_epoch="$stamp_epoch"
        newest_suffix="$suffix"
      fi
      if [ "$stamp_epoch" -lt "$cutoff" ]; then
        expired+=("$entry")
      fi
    done

    for entry in "''${expired[@]}"; do
      [ "$entry" != "$newest" ] || continue
      name="''${entry##*/}"
      if btrfs subvolume delete --recursive "$entry" > /dev/null 2>&1; then
        log "pruned $name"
      else
        fail "could not prune $name"
      fi
    done
  '';
in
{
  options.my.storage.root = {
    mode = lib.mkOption {
      type = lib.types.enum [
        "ephemeral"
        "persistent"
      ];
      default = "ephemeral";
      description = "Whether the system root is recreated at boot or kept across boots.";
    };

    keepDays = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 7;
      description = "How many days of old root subvolumes to retain.";
    };
  };

  config = lib.mkIf (cfg.mode == "ephemeral") {
    # The unit wrapper references the script and the initrd has no btrfs-progs: storePaths
    # copies the script into the initrd, extraBin provides the command it calls.
    boot.initrd.systemd = {
      storePaths = [ rollback ];
      extraBin.btrfs = "${pkgs.btrfs-progs}/bin/btrfs";
    };

    boot.initrd.systemd.services.rollback = {
      description = "Recreate the ephemeral Btrfs root subvolume";
      wantedBy = [ "initrd.target" ];
      requires = [ cryptsetupUnit ];
      after = [
        cryptsetupUnit
        "dev-mapper-${luksNames.root}.device"
        "systemd-hibernate-resume.service"
      ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig.Type = "oneshot";
      environment.PATH = "/bin:/sbin";
      script = "${rollback}";
    };

    # /run survives into stage 2, so the initrd leaves a marker there and this reports it.
    systemd.services.rollback-failure-report = {
      description = "Report a failed ephemeral root rollback";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if [ ! -e /run/rollback-failed ]; then
          exit 0
        fi

        message="ephemeral root rollback failed; see the preceding boot logs"
        printf '%s\n' "$message" >&2
        ${pkgs.util-linux}/bin/wall "$message"
        exit 1
      '';
    };
  };
}
