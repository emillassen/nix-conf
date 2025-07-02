{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Common mount options for all SMB shares
  mkSmbMount = share: {
    device = "//${config.sops.placeholder.smb_server_ip}/${share}";
    fsType = "cifs";
    options =
      let
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.mount-timeout=5s";
      in
      [
        automount_opts
        "credentials=${config.sops.templates."smb-credentials".path}"
        "uid=${toString config.users.users.emil.uid}"
        "gid=${toString config.users.groups.users.gid}"
        "forceuid"
        "forcegid"
        "vers=3.1.1"
        "iocharset=utf8"
        "file_mode=0664"
        "dir_mode=0775"
        "cache=strict"
        "rsize=1048576"
        "wsize=1048576"
      ];
  };

  # List of shares to mount
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
in
{
  # For mount.cifs, required unless domain name resolution is not needed.
  environment.systemPackages = [ pkgs.cifs-utils ];

  # Use sops-nix built-in template feature for SMB credentials
  sops.templates."smb-credentials" = {
    content = ''
      username=${config.sops.placeholder.smb_username}
      password=${config.sops.placeholder.smb_password}
      domain=
    '';
    owner = config.users.users.emil.name;
    group = config.users.groups.users.name;
    mode = "0400";
  };

  # Generate all mount points
  fileSystems = lib.listToAttrs (
    map (share: {
      name = "/mnt/${share}";
      value = mkSmbMount share;
    }) shares
  );
}
