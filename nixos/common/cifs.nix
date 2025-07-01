{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Common mount options for all SMB shares
  mkSmbMount = share: {
    device = "//192.168.1.30/${share}";
    fsType = "cifs";
    options =
      let
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.mount-timeout=5s";
      in
      [
        automount_opts
        "credentials=/etc/nixos/smb-secrets"
        "uid=1000"
        "gid=100"
        "forceuid"
        "forcegid"
        "vers=3.1.1"
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

  # Systemd service to generate SMB credentials from sops secrets
  systemd.services.generate-smb-secrets = {
    description = "Generate SMB credentials from sops secrets";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-nix.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "generate-smb-secrets" ''
        mkdir -p /etc/nixos
        cat > /etc/nixos/smb-secrets << EOF
        username=$(cat ${config.sops.secrets.smb_username.path})
        password=$(cat ${config.sops.secrets.smb_password.path})
        domain=
        EOF
        chmod 600 /etc/nixos/smb-secrets
      '';
    };
  };

  # Generate all mount points
  fileSystems = lib.listToAttrs (
    map (share: {
      name = "/mnt/${share}";
      value = mkSmbMount share;
    }) shares
  );
}
