{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  nixpkgs.overlays = [
    inputs.nix-vscode-extensions.overlays.default
  ];

  # Packages that are used by VSCode and/or the extensions
  home.packages =
    with pkgs;
    lib.mkAfter [
      ansible-lint
      claude-code
      nixd
      nixfmt-rfc-style
      pre-commit
      yamllint
    ];

  programs.vscode = {
    enable = true;
    package = pkgs.vscode; # Could also use VSCodium for better privacy
    profiles.default = {

      # Extensions
      # Use vscode-marketplace for extensions from nix-vscode-extensions (newest)
      # Use vscode-extensions for extensions from nixpkgs
      extensions = with pkgs; [
        vscode-marketplace.anthropic.claude-code
        vscode-marketplace.catppuccin.catppuccin-vsc
        vscode-marketplace.catppuccin.catppuccin-vsc-icons
        vscode-marketplace.eamodio.gitlens
        vscode-marketplace.esbenp.prettier-vscode
        vscode-marketplace.github.copilot
        vscode-extensions.github.copilot-chat
        vscode-marketplace.github.vscode-github-actions
        vscode-extensions.github.vscode-pull-request-github
        vscode-marketplace.jeff-hykin.better-dockerfile-syntax
        vscode-marketplace.jeff-hykin.better-nix-syntax
        vscode-marketplace.jnoortheen.nix-ide
        vscode-marketplace.pkief.material-icon-theme
        vscode-marketplace.redhat.ansible
        vscode-marketplace.redhat.vscode-yaml
        vscode-marketplace.saoudrizwan.claude-dev
        vscode-marketplace.streetsidesoftware.code-spell-checker
        vscode-marketplace.usernamehw.errorlens
      ];

      # User settings
      userSettings = {
        # Disable telemetry
        "telemetry.telemetryLevel" = "off";
        "telemetry.feedback.enabled" = false;
        "redhat.telemetry.enabled" = false;
        "gitlens.telemetry.enabled" = false;

        # Disable automatic updates and hide release notes
        "extensions.autoCheckUpdates" = false;
        "extensions.autoUpdate" = false;
        "update.showReleaseNotes" = false;
        "update.mode" = "none";

        # Privacy settings
        "workbench.enableExperiments" = false;

        # Nix formatting
        "nix.formatterPath" = "${pkgs.nixfmt-rfc-style}/bin/nixfmt";
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "${pkgs.nixd}/bin/nixd";
        "[nix]" = {
          "editor.formatOnSave" = true;
          "editor.defaultFormatter" = "jnoortheen.nix-ide";
        };

        # General settings
        "editor.fontFamily" = "Hack Nerd Font Mono";
        "editor.fontSize" = 14;
        "editor.formatOnSave" = true;
        "editor.bracketPairColorization.enabled" = true;
        "editor.minimap.enabled" = false;
        "editor.rulers" = [
          80
          120
        ];

        # Theme
        "workbench.colorTheme" = "Catppuccin Mocha";
        "workbench.iconTheme" = "catppuccin-mocha";

        # Git integration
        "git.autofetch" = false;
        "git.confirmSync" = false;
        "git.enableSmartCommit" = true;

        # Terminal integration
        "terminal.integrated.fontFamily" = "Hack Nerd Font Mono";
        "terminal.integrated.fontSize" = 14;
        "terminal.integrated.defaultProfile.linux" = "zsh";

        # Add words to spellcheck
        "cSpell.userWords" = [
          "substituters"
          "nixos"
          "cachix"
          "nixpkgs"
          "disko"
          "pkgs"
        ];
      };

      # Keybindings
      keybindings = [
        {
          key = "ctrl+shift+f";
          command = "editor.action.formatDocument";
          when = "editorTextFocus";
        }
        {
          key = "ctrl+k ctrl+t";
          command = "workbench.action.selectTheme";
        }
      ];
    };
  };
}
