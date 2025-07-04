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

  # Mount script that reads secrets at runtime
  mountScript =
    share:
    pkgs.writeShellScript "mount-${share}" ''
      SERVER_IP=$(cat ${config.sops.secrets.smb_server_ip.path})
      exec ${pkgs.util-linux}/bin/mount -t cifs \
        -o credentials=/run/secrets/rendered/smb-credentials,uid=${toString config.users.users.emil.uid},gid=${toString config.users.groups.users.gid},file_mode=0755,dir_mode=0755,vers=3.1.1 \
        "//$SERVER_IP/${share}" "/mnt/${share}"
    '';

  # Unmount script
  umountScript =
    share:
    pkgs.writeShellScript "umount-${share}" ''
      exec ${pkgs.util-linux}/bin/umount "/mnt/${share}"
    '';
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

  # Create mount points
  systemd.tmpfiles.rules = map (
    share: "d /mnt/${share} 0755 ${config.users.users.emil.name} users -"
  ) shares;

  # Create systemd services for each share
  systemd.services = lib.listToAttrs (
    map (share: {
      name = "mount-${share}";
      value = {
        description = "Mount SMB share ${share}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${mountScript share}";
          ExecStop = "${umountScript share}";
        };
      };
    }) shares
  );
}
