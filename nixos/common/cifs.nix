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
    device = "//192.168.1.30/${share}"; # Hardcoded IP like your old config
    fsType = "cifs";
    options = [
      # Systemd automount options
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.mount-timeout=5s"
      # SMB options
      "credentials=/run/secrets/rendered/smb-credentials"
      "uid=1000"
      "gid=100"
      "forceuid"
      "forcegid"
      "file_mode=0755"
      "dir_mode=0755"
      "vers=3.1.1"
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
