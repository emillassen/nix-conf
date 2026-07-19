{
  description = "Emil's NixOS config";

  # the nixConfig here only affects commands run on the flake itself (useful at
  # install time, before the system config applies) — cache.nixos.org and its
  # key stay active as the built-in defaults. Honored because emil is in
  # nix.settings.trusted-users (nixos/configuration.nix).
  nixConfig = {
    extra-substituters = [
      # nix community's cache server
      "https://nix-community.cachix.org"
      # numtide cache for llm-agents.nix prebuilt AI agents
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    # Nixpkgs (primary channel)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # Stable nixpkgs, exposed as pkgs.stable via the stable-packages overlay
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";

    # Adds disko support for partitioning, formatting and LUKS on disks
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Home manager
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # NixOS profiles to optimize settings for different hardware
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";

    # VSCode extensions
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    nix-vscode-extensions.inputs.nixpkgs.follows = "nixpkgs";

    # Secrets management
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Pre-commit hooks (cachix/git-hooks.nix is the renamed pre-commit-hooks.nix)
    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";

    # Nixvim - Neovim configuration with Nix
    nixvim.url = "github:nix-community/nixvim";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";

    # Catppuccin theming for NixOS and Home Manager
    catppuccin.url = "github:catppuccin/nix";
    catppuccin.inputs.nixpkgs.follows = "nixpkgs";

    # AI coding agents (claude-code, opencode, gemini-cli, ...)
    # Keeps its own pinned nixpkgs on purpose so the numtide binary cache
    # applies - do NOT set inputs.nixpkgs.follows or the agents rebuild locally.
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      nixos-hardware,
      sops-nix,
      pre-commit-hooks,
      ...
    }@inputs:
    let
      inherit (self) outputs;
      # Supported systems for your flake packages, shell, etc.
      # (linux only — the custom packages and NixOS config don't target darwin)
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # This is a function that generates an attribute by calling a function you
      # pass to it, with each system as an argument
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # Your custom packages
      # Accessible through 'nix build', 'nix shell', etc
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        import ./pkgs pkgs
      );
      # Formatter for your nix files, available through 'nix fmt'
      # (nixfmt-tree = treefmt+nixfmt; plain nixfmt only reads stdin when nix
      # fmt invokes it without arguments, which breaks on Nix >= 2.25)
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      # Your custom packages and modifications, exported as overlays
      overlays = import ./overlays { inherit inputs; };
      # Reusable nixos modules you might want to export
      # These are usually stuff you would upstream into nixpkgs
      nixosModules = import ./modules/nixos;
      # Reusable home-manager modules you might want to export
      # These are usually stuff you would upstream into home-manager
      # ('homeModules' is the standard output name; 'homeManagerModules' is
      # legacy and makes 'nix flake check' warn about an unknown output)
      homeModules = import ./modules/home-manager;

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
          pre-commit-check = pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              nixfmt.enable = true;
              statix.enable = true;
              deadnix.enable = true;
              check-added-large-files.enable = true;
              end-of-file-fixer.enable = true;
              trim-trailing-whitespace.enable = true;
              mixed-line-endings.enable = true;
              check-case-conflicts.enable = true;
              check-merge-conflicts.enable = true;
              detect-private-keys.enable = true;

              prettier = {
                enable = true;
                types_or = [
                  "yaml"
                  "markdown"
                ];
                excludes = [ "^secrets/.*" ];
              };

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
            inputs.catppuccin.nixosModules.catppuccin
          ];
        };
      };
    };
}
