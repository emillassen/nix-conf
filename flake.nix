{
  description = "Emil's NixOS config";

  # the nixConfig here only affects the flake itself, not the system configuration!
  nixConfig = {
    # override the default substituters
    substituters = [
      # cache mirror located in China
      # status: https://mirror.sjtu.edu.cn/
      #"https://mirror.sjtu.edu.cn/nix-channels/store"
      # status: https://mirrors.ustc.edu.cn/status/
      #"https://mirrors.ustc.edu.cn/nix-channels/store"

      "https://cache.nixos.org"

      # nix community's cache server
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # You can access packages and modules from different nixpkgs revs
    # at the same time. Here's an working example:
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";

    # Adds disko support for partitioning, formatting and LUKS on disks
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Home manager
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # NixOS profiles to optimize settings for different hardware
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # VSCode extensions
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    # Secrets management
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Pre-commit hooks
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self
    , nixpkgs
    , disko
    , nixos-hardware
    , sops-nix
    , pre-commit-hooks
    , ...
    }@inputs:
    let
      inherit (self) outputs;
      # Supported systems for your flake packages, shell, etc.
      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      # This is a function that generates an attribute by calling a function you
      # pass to it, with each system as an argument
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});
      # Formatter for your nix files, available through 'nix fmt'
      # Other options beside 'alejandra' include 'nixpkgs-fmt'
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };
      # Reusable nixos modules you might want to export
      # These are usually stuff you would upstream into nixpkgs
      nixosModules = import ./modules/nixos;
      # Reusable home-manager modules you might want to export
      # These are usually stuff you would upstream into home-manager
      homeManagerModules = import ./modules/home-manager;

      # Development shells
      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          inherit (self.checks.${system}.pre-commit-check) shellHook;
          buildInputs = self.checks.${system}.pre-commit-check.enabledPackages;

          packages = with nixpkgs.legacyPackages.${system}; [
            sops
            age
          ];
        };
      });

      # Flake checks for validation
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # Validate that all secrets are properly encrypted
          secrets-encrypted =
            pkgs.runCommand "check-secrets-encrypted"
              {
                nativeBuildInputs = [ pkgs.sops ];
              }
              ''
                cd ${./.}/secrets

                echo "Checking that all secret files are encrypted..."
                failed=0

                for file in *.yaml; do
                  [[ "$file" == "*.yaml" ]] && continue

                  if [[ "$file" != ".sops.yaml" ]]; then
                    echo "Checking $file..."
                    # Check if file contains sops metadata instead of trying to decrypt
                    if grep -q "sops:" "$file" && grep -q "age:" "$file"; then
                      echo "✓ $file is properly encrypted (contains sops metadata)"
                    else
                      echo "ERROR: $file is not properly encrypted or is corrupted"
                      ((failed++))
                    fi
                  fi
                done

                if [[ $failed -eq 0 ]]; then
                  echo "All secrets are properly encrypted!"
                  touch $out
                else
                  echo "$failed secret(s) failed validation"
                  exit 1
                fi
              '';

          # Pre-commit hooks check
          pre-commit-check = pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              # Nix formatting
              nixfmt-rfc-style.enable = true;

              # Nix linting
              statix.enable = true;

              # Dead code detection
              deadnix.enable = true;

              # Check for large files
              check-added-large-files.enable = true;

              # YAML formatting
              prettier = {
                enable = true;
                types_or = [
                  "yaml"
                  "markdown"
                ];
              };

              # Custom hook for sops files
              sops-encrypted = {
                enable = true;
                name = "sops-encrypted";
                entry = "${pkgs.writeShellScript "check-sops" ''
                  for file in secrets/*.yaml; do
                    [[ "$file" == "secrets/*.yaml" ]] && continue
                    if [[ "$file" != *".sops.yaml" ]]; then
                      if ! grep -q "sops:" "$file"; then
                        echo "ERROR: $file appears unencrypted!"
                        exit 1
                      fi
                    fi
                  done
                ''}";
                files = "^secrets/.*\\.yaml$";
              };
            };
          };
        }
      );

      # NixOS configuration entrypoint
      # Available through 'nixos-rebuild --flake .#your-hostname'
      nixosConfigurations = {
        fw13 = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = [
            # > Our main nixos configuration file <
            ./nixos/configuration.nix
            disko.nixosModules.disko
            nixos-hardware.nixosModules.framework-13-7040-amd
            sops-nix.nixosModules.sops

            # given the users in this list the right to specify additional substituters via:
            # 1. `nixConfig.substituers` in `flake.nix`
            { nix.settings.trusted-users = [ "emil" ]; }
          ];
        };
      };
    };
}
