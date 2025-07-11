{ pkgs, ... }:
{
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty;
    settings = {
      #https://ghostty.org/docs/config/reference
      theme = "catppuccin-mocha";
      font-family = "Hack Nerd Font Mono";
      font-size = 10;
      font-ligatures = true;
      cursor-style = "block";
      scrollback-limit = 100000;
      window-height = 70;
      window-width = 112;
      window-padding-x = 0;
      window-padding-y = 0;
      window-theme = "ghostty";
      #gtk-adwaita = "false";
      gtk-tabs-location = "bottom";
      clipboard-read = "allow";
      clipboard-paste-protection = false;
      #window-decoration = false;
      shell-integration = "zsh";
    };
  };
}
