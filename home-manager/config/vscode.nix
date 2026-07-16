{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  # The nix-vscode-extensions overlay (pkgs.vscode-marketplace.*) is applied to
  # the shared system nixpkgs instance in nixos/configuration.nix.

  # Packages that are used by VSCode and/or the extensions
  home.packages =
    with pkgs;
    lib.mkAfter [
      ansible-lint
      # CLI backing the claude-code VSCode extension (direct flake reference
      # per upstream's README, keeping its binary cache)
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
      nixd
      nixfmt
      pre-commit
      #python3Full
      yamllint
    ];

  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    profiles.default = {

      # Use vscode-marketplace for extensions from nix-vscode-extensions (newest)
      # Use vscode-extensions for extensions from nixpkgs
      extensions = with pkgs; [
        vscode-marketplace.anthropic.claude-code
        # catppuccin-vsc + catppuccin-vsc-icons are provided by the Catppuccin
        # module (config/catppuccin.nix)
        vscode-marketplace.eamodio.gitlens
        vscode-marketplace.esbenp.prettier-vscode
        vscode-marketplace.github.vscode-github-actions
        vscode-extensions.github.vscode-pull-request-github
        vscode-marketplace.jeff-hykin.better-dockerfile-syntax
        vscode-marketplace.jeff-hykin.better-nix-syntax
        vscode-marketplace.jnoortheen.nix-ide
        vscode-marketplace.ms-python.python
        vscode-marketplace.ms-python.vscode-pylance
        vscode-marketplace.pkief.material-icon-theme
        vscode-marketplace.redhat.ansible
        vscode-marketplace.redhat.vscode-yaml
        vscode-marketplace.saoudrizwan.claude-dev
        vscode-marketplace.usernamehw.errorlens
      ];

      userSettings = {
        "telemetry.telemetryLevel" = "off";
        "telemetry.feedback.enabled" = false;
        "redhat.telemetry.enabled" = false;
        "gitlens.telemetry.enabled" = false;
        "extensions.ignoreRecommendations" = true;
        "workbench.tips.enabled" = false;
        "workbench.welcomePage.walkthroughs.openOnInstall" = false;
        "workbench.enableExperiments" = false;

        "extensions.autoCheckUpdates" = false;
        "extensions.autoUpdate" = false;
        "update.showReleaseNotes" = false;
        "update.mode" = "none";

        "nix.formatterPath" = "${pkgs.nixfmt}/bin/nixfmt";
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "${pkgs.nixd}/bin/nixd";
        "[nix]" = {
          "editor.formatOnSave" = true;
          "editor.defaultFormatter" = "jnoortheen.nix-ide";
        };

        "[jsonc]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };

        "editor.fontFamily" = "Hack Nerd Font Mono";
        "editor.fontSize" = 14;
        "editor.formatOnSave" = true;
        "editor.bracketPairColorization.enabled" = true;
        "editor.minimap.enabled" = false;
        "editor.rulers" = [
          80
          120
        ];

        # workbench.colorTheme + iconTheme are set by Catppuccin
        # (config/catppuccin.nix)

        "git.autofetch" = false;
        "git.confirmSync" = false;
        "git.enableSmartCommit" = true;

        "terminal.integrated.fontFamily" = "Hack Nerd Font Mono";
        "terminal.integrated.fontSize" = 14;
        "terminal.integrated.defaultProfile.linux" = "zsh";
      };

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
