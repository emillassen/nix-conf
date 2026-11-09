# KDE settings that Plasma keeps in files it also writes itself, so they are set
# key by key with kwriteconfig6 at every switch instead of owning the file
# (kded5rc also holds the Background Services toggled in System Settings).
{
  lib,
  pkgs,
  ...
}:
{
  # kded's "Trash Change Notifier" (trashdirnotify) watches every trash folder
  # KIO has made, including the .Trash-1000 on each NAS share a file was ever
  # deleted from (~/.config/trashrc [NetworkShares]). When such a share idles
  # out of its automount (x-systemd.idle-timeout=60, nixos/common/cifs.nix), the
  # module checks whether its trash folder still exists, and that check mounts
  # the share again - so every share it knows stays mounted, remounting each
  # minute. Unloading the module live stopped the remounts at once. Its loss is
  # small: KIO's trash announces its own changes, so only trash changes made by
  # non-KDE tools stop refreshing the Trash icon at once.
  # kded6 still reads kded5rc; the module stays off until it is loaded by name,
  # which nothing in KIO does.
  home.activation.disableTrashDirNotify = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe' pkgs.kdePackages.kconfig "kwriteconfig6"} \
      --file kded5rc --group Module-trashdirnotify --key autoload false
  '';
}
