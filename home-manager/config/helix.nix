{ pkgs, ... }:
{
  home.packages =
    with pkgs;
    lib.mkAfter [
      nixd # Nix language server
      nixfmt # Nix code formatter (RFC style)
      yaml-language-server # YAML language server
      prettier # Code formatter for multiple languages
      marksman # Markdown language server
      taplo # TOML language server and formatter
    ];

  programs.helix = {
    enable = true;
    settings = {
      theme = "catppuccin_mocha";
      editor = {
        line-number = "relative";
        cursorline = true;
        color-modes = true;
        cursor-shape = {
          normal = "block";
          insert = "bar";
          select = "underline";
        };
        indent-guides = {
          render = true;
        };
      };
    };
    languages.language = [
      {
        name = "nix";
        auto-format = true;
        language-servers = [ "nixd" ];
        formatter.command = pkgs.lib.getExe pkgs.nixfmt;
      }
      {
        name = "yaml";
        auto-format = true;
        language-servers = [ "yaml-language-server" ];
        formatter = {
          command = pkgs.lib.getExe pkgs.prettier;
          args = [
            "--parser"
            "yaml"
          ];
        };
      }
      {
        name = "markdown";
        auto-format = true;
        language-servers = [ "marksman" ];
        formatter = {
          command = pkgs.lib.getExe pkgs.prettier;
          args = [
            "--parser"
            "markdown"
          ];
        };
      }
      {
        name = "json";
        auto-format = true;
        language-servers = [ "prettier" ];
        formatter = {
          command = pkgs.lib.getExe pkgs.prettier;
          args = [
            "--parser"
            "json"
          ];
        };
      }
    ];
  };
}
