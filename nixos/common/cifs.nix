{
  pkgs,
  lib,
  config,
  ...
}:
let
  shares = [
    "appdata"
    "backups"
    "books"
    "domains"
    "downloads"
    "games"
    "isos"
    "movies"
    "nextcloud"
    "series"
  ];

  # Common mount options for all SMB shares
  mkSmbMount = share: {
    device = "//192.168.1.30/${share}";
    fsType = "cifs";
    options = [
      # Systemd automount options
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.mount-timeout=15s"
      # SMB options
      "credentials=${config.sops.templates."smb-credentials".path}"
      "uid=1000"
      "gid=100"
      "forceuid"
      "forcegid"
      # Files are data, not programs: 0755 marked every video, epub and NFO
      # on the NAS executable (green in ls, "Run" in Dolphin). A script on a
      # share now runs with `bash script.sh` instead of `./script.sh`.
      "file_mode=0644"
      "dir_mode=0755"
      "vers=3.1.1"
      # The NAS is Unraid, whose user shares (shfs) do not keep inode numbers
      # unique. With the server's numbers in use the kernel eventually logs
      # "Inode number collision detected" and switches them off for the rest
      # of the mount - on 2026-11-07 that happened 3s into a drtv-dl run into
      # /mnt/series, which then left a new series folder empty and its other
      # files half-written. Use client-side numbers from the start, as the
      # kernel's own message advises; nothing here relies on hardlinks.
      "noserverino"
    ];
  };
in
{
  # Install required packages
  environment.systemPackages = [ pkgs.cifs-utils ];

  # SMB credentials template
  sops.templates."smb-credentials" = {
    content = ''
      username=${config.sops.placeholder.smb_username}
      password=${config.sops.placeholder.smb_password}
      domain=
    '';
    owner = "root";
    group = "root";
    mode = "0600";
  };

  # Generate all mount points using fileSystems
  fileSystems = lib.listToAttrs (
    map (share: {
      name = "/mnt/${share}";
      value = mkSmbMount share;
    }) shares
  );

  # Ensure mount points exist
  systemd.tmpfiles.rules = map (share: "d /mnt/${share} 0755 emil users -") shares;
}
