{
  # Partition only the free space beside Windows.
  imports = [
    ../../profiles/base.nix
    ((import ../../lib/storage.nix).mountsFor {
      espUUID = "b8442cfc-d017-46b0-a8fb-76d819a4a4af";
      rootUUID = "07a126c0-2379-4aae-a898-467d76ce405c";
    })
  ];

  system.stateVersion = "26.11";
}
