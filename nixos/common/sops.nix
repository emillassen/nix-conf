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
      # luks_key (secrets/luks.yaml) is deliberately NOT declared here: it's only
      # consumed at install time (scripts/pre-install-secrets.sh decrypts it for
      # disko). Declaring it would needlessly place the plaintext LUKS key in
      # /run/secrets on every boot.
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
            # luks_key is intentionally excluded: it's only used at install time,
            # so it's never present here to validate (see the sops.secrets comment).
            # The paths are taken from the sops-nix config because they differ per
            # secret: neededForUsers secrets (emil_password_hash) live under
            # /run/secrets-for-users, the rest under /run/secrets.
            # Note: writeShellApplication runs with `set -e`, so the counter must be
            # incremented with an arithmetic *assignment* — `((failed++))` returns
            # a non-zero status when failed is 0 and would abort the whole script.
            for secret_path in ${
              lib.escapeShellArgs (
                map (name: config.sops.secrets.${name}.path) [
                  "smb_username"
                  "smb_password"
                  "emil_password_hash"
                ]
              )
            }; do
              if [[ ! -r "$secret_path" ]]; then
                echo "ERROR: $secret_path not readable"
                failed=$((failed + 1))
              elif [[ ! -s "$secret_path" ]]; then
                echo "ERROR: $secret_path is empty"
                failed=$((failed + 1))
              fi
            done
            exit "$failed"
          '';
        }
      );
    };
  };
}
