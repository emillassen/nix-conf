{
  config,
  pkgs,
  ...
}:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode; # Could also use VSCodium for better privacy
    profiles.default = {

      # Extensions
      extensions = with pkgs.vscode-extensions; [
        # Nix language support
        jnoortheen.nix-ide
        kamadorueda.alejandra # You already have this in home.nix

        # General development
        eamodio.gitlens
        usernamehw.errorlens

        # Themes and UI
        catppuccin.catppuccin-vsc
        catppuccin.catppuccin-vsc-icons
        pkief.material-icon-theme

      ];

      # User settings
      userSettings = {
        # Disable telemetry
        "telemetry.telemetryLevel" = "off";
        "telemetry.enableCrashReporter" = false;
        "telemetry.enableTelemetry" = false;
        "extensions.autoCheckUpdates" = false;
        "extensions.autoUpdate" = false;
        "update.mode" = "none";
        "update.showReleaseNotes" = false;

        # Privacy settings
        "workbench.enableExperiments" = false;
        "workbench.settings.enableNaturalLanguageSearch" = false;
        "npm.fetchOnlinePackageInfo" = false;

        # Nix formatting
        "nix.formatterPath" = "${pkgs.nixfmt-rfc-style}/bin/nixfmt";
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "${pkgs.nixd}/bin/nixd";
        "[nix]" = {
          "editor.formatOnSave" = true;
          "editor.defaultFormatter" = "jnoortheen.nix-ide";
        };

        # General settings
        "editor.fontFamily" = "'Hack Nerd Font Mono', 'monospace'";
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
        "terminal.integrated.fontFamily" = "'Hack Nerd Font Mono'";
        "terminal.integrated.fontSize" = 12;
        "terminal.integrated.defaultProfile.linux" = "zsh";
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
