{pkgs, lib, ...}: let
  mkSmbMount = share: {
    device = "//192.168.1.30/${share}";
    fsType = "cifs";
    options = [
      "x-systemd.automount"
      "noauto"
      "x-systemd.idle-timeout=60"
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
      "credentials=/run/credentials/smb-creds"
      "uid=1000"
      "gid=100"
    ];
  };

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
in {
  environment.systemPackages = [pkgs.cifs-utils];
  
  fileSystems = lib.genAttrs 
    (map (share: "/mnt/${share}") shares)
    (mountPoint: mkSmbMount (lib.last (lib.splitString "/" mountPoint)));

  systemd.services."smb-credentials" = {
    description = "Load SMB credentials";
    before = [ "remote-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Create credential from your existing file
      ExecStart = "${pkgs.coreutils}/bin/install -m 0600 /etc/nixos/smb-secrets /run/credentials/smb-creds";
    };
  };
}
