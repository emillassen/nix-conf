{
  lib,
  pkgs,
  inputs,
  ...
}:
{
  nixpkgs.overlays = [ inputs.nix-vscode-extensions.overlays.default ];

  # Packages that are used by VSCode and/or the extensions
  home.packages =
    with pkgs;
    lib.mkAfter [
      ansible-lint
      claude-code
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
        vscode-marketplace.catppuccin.catppuccin-vsc
        vscode-marketplace.catppuccin.catppuccin-vsc-icons
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

        "workbench.colorTheme" = "Catppuccin Mocha";
        "workbench.iconTheme" = "catppuccin-mocha";

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
