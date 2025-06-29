{
  config,
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
      extensions = with pkgs.vscode-marketplace; [
        anthropic.claude-code
        catppuccin.catppuccin-vsc
        catppuccin.catppuccin-vsc-icons
        eamodio.gitlens
        github.copilot
        github.copilot-chat
        github.vscode-github-actions
        github.vscode-pull-request-github
        jeff-hykin.better-dockerfile-syntax
        jeff-hykin.better-nix-syntax
        jnoortheen.nix-ide
        pkief.material-icon-theme
        redhat.ansible
        redhat.vscode-yaml
        saoudrizwan.claude-dev
        streetsidesoftware.code-spell-checker
        usernamehw.errorlens
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
