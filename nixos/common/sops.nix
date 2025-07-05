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

      # System-level secrets
      emil_password_hash = {
        sopsFile = ../../secrets/system.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
        # Ensure this secret is available during early boot
        neededForUsers = true;
      };
    };
  };

  # Validation service to check secrets are properly decrypted
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
            echo "Validating sops secrets..."

            failed=0
            errors=()

            # Check all secrets in one loop
            for secret in smb_username smb_password emil_password_hash; do
              secret_path="/run/secrets/$secret"

              if [[ ! -r "$secret_path" ]]; then
                echo "ERROR: Secret $secret not readable"
                errors+=("Secret $secret not readable")
                ((failed++))
              elif [[ ! -s "$secret_path" ]]; then
                echo "ERROR: Secret $secret is empty"
                errors+=("Secret $secret is empty")
                ((failed++))
              else
                echo "✓ Secret $secret is available and non-empty"
              fi
            done

            # Report results
            if [[ $failed -eq 0 ]]; then
              echo "All secrets validated successfully!"
            else
              echo
              echo "=== VALIDATION SUMMARY ==="
              echo "Found $failed issue(s):"
              printf '  - %s\n' "''${errors[@]}"
              echo "Please fix these issues and try again."
              exit 1
            fi
          '';
        }
      );
    };
  };
}
