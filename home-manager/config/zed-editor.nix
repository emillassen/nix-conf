{
  lib,
  pkgs,
  ...
}:
{
  # Packages that are used by Zed and/or the extensions
  home.packages =
    with pkgs;
    lib.mkAfter [
      ansible-lint # Ansible playbook linter
      nixd # Nix language server
      nixfmt # Nix code formatter (RFC style)
    ];

  programs.zed-editor = {
    enable = true;
    package = pkgs.zed-editor;
    extensions = [
      "ansible"
      "caddyfile"
      "catppuccin"
      "catppuccin-icons"
      "dockerfile"
      "dockercompose"
      "git-firefly"
      "nix"
      "toml"
    ];

    # https://zed.dev/docs/reference/all-settings
    userSettings = {
      theme = "Catppuccin Mocha";
      icon_theme = "Catppuccin Mocha";
      buffer_font_family = "Hack Nerd Font Mono";
      buffer_font_size = 14;
      features.copilot = false;
      telemetry = {
        metrics = false;
        diagnostics = false;
      };
    };
  };
}
