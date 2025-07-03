{ pkgs, ... }:
{
  home.packages =
    with pkgs;
    lib.mkAfter [
      nixd
      nixfmt-rfc-style
      yaml-language-server
      prettier
      marksman
      taplo
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
        formatter.command = "${pkgs.nixfmt-rfc-style}/bin/nixfmt";
      }
      {
        name = "yaml";
        auto-format = true;
        language-servers = [ "yaml-language-server" ];
        formatter = {
          command = "${pkgs.prettier}/bin/prettier";
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
          command = "${pkgs.prettier}/bin/prettier";
          args = [
            "--parser"
            "markdown"
          ];
        };
      }
      {
        name = "json";
        auto-format = true;
        language-servers = [ "taplo" ];
        formatter = {
          command = "${pkgs.prettier}/bin/prettier";
          args = [
            "--parser"
            "json"
          ];
        };
      }
    ];
  };
}
