{
  config,
  lib,
  pkgs,
  ...
}:
let
  mkSmbSecret = name: {
    sopsFile = ../../secrets/smb.yaml;
    key = name;
    owner = config.users.users.emil.name;
    group = config.users.groups.users.name;
    mode = "0400";
  };
in
{
  environment.systemPackages = with pkgs; [
    age
    sops
    bitwarden-cli
    jq
  ];

  sops = {
    defaultSopsFormat = "yaml";

    age = {
      keyFile = "${config.users.users.emil.home}/.config/sops/age/keys.txt";
      generateKey = false;
    };

    secrets = {
      smb_username = mkSmbSecret "smb_username";
      smb_password = mkSmbSecret "smb_password";

      emil_password_hash = {
        sopsFile = ../../secrets/system.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
        neededForUsers = true;
      };
      luks_key = {
        sopsFile = ../../secrets/luks.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
        neededForUsers = true;
      };
    };
  };

  systemd.services.sops-secrets-validation = {
    description = "Validate sops secrets are accessible";
    wantedBy = [ "multi-user.target" ];
    after = [
      "sops-nix.service"
      "systemd-user-sessions.service"
    ];
    requires = [ "sops-nix.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "validate-sops-secrets";
          runtimeInputs = with pkgs; [ coreutils ];
          text = ''
            failed=0
            for secret in smb_username smb_password emil_password_hash; do
              secret_path="/run/secrets/$secret"
              if [[ ! -r "$secret_path" ]]; then
                echo "ERROR: $secret not readable"
                ((failed++))
              elif [[ ! -s "$secret_path" ]]; then
                echo "ERROR: $secret is empty"
                ((failed++))
              fi
            done
            exit "$failed"
          '';
        }
      );
    };
  };
}
