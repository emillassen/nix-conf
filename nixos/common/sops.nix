{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Helper function to reduce boilerplate for SMB secrets
  mkSmbSecret = name: {
    sopsFile = ../../secrets/smb.yaml;
    owner = config.users.users.emil.name;
    group = config.users.groups.users.name;
    mode = "0400";
  };
in
{
  environment.systemPackages = with pkgs; [
    age
    sops
  ];
 
 # sops-nix configuration
  sops = {
    defaultSopsFormat = "yaml";

    age = {
      keyFile = "${config.users.users.emil.home}/.config/sops/age/keys.txt";
      # Will generate a new key if it doesn't exist
      generateKey = true;
    };

    secrets = {
      # SMB/CIFS credentials from dedicated file
      smb_username = mkSmbSecret "smb_username";
      smb_password = mkSmbSecret "smb_password";
      smb_server_ip = mkSmbSecret "smb_server_ip";
      
      # System-level secrets
      emil_password_hash = {
        sopsFile = ../../secrets/system.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };

  # Validation service to check secrets are properly decrypted
  systemd.services.sops-secrets-validation = {
    description = "Validate sops secrets are accessible";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-nix.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = config.users.users.emil.name;
      Group = config.users.groups.users.name;
      ExecStart = lib.getExe (pkgs.writeShellApplication {
        name = "validate-sops-secrets";
        runtimeInputs = with pkgs; [ coreutils ];
        text = ''
          echo "Validating sops secrets..."

          # Check required SMB secrets
          for secret in smb_username smb_password smb_server_ip; do
            secret_path="/run/secrets/$secret"
            if [[ ! -r "$secret_path" ]]; then
              echo "ERROR: Secret $secret not readable at $secret_path"
              exit 1
            fi

            # Check secret is not empty
            if [[ ! -s "$secret_path" ]]; then
              echo "ERROR: Secret $secret is empty"
              exit 1
            fi

            echo "✓ Secret $secret is available and non-empty"
          done

          # Check system secrets
          for secret in emil_password_hash; do
            secret_path="/run/secrets/$secret"
            if [[ ! -r "$secret_path" ]]; then
              echo "ERROR: Secret $secret not readable at $secret_path"
              exit 1
            fi

            # Check secret is not empty
            if [[ ! -s "$secret_path" ]]; then
              echo "ERROR: Secret $secret is empty"
              exit 1
            fi

            echo "✓ Secret $secret is available and non-empty"
          done

          echo "All secrets validated successfully!"
        '';
      });
    };
  };
}
