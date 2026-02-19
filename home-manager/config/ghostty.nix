{ pkgs, ... }:
{
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty;
    settings = {
      #https://ghostty.org/docs/config/reference
      theme = "Catppuccin Mocha";
      font-family = "Hack Nerd Font Mono";
      font-size = 10;
      cursor-style = "block";
      cursor-style-blink = true;
      bell-features = "no-audio,no-system";
      scrollback-limit = 100000;
      window-height = 70;
      window-width = 112;
      window-padding-x = 0;
      window-padding-y = 0;
      window-theme = "ghostty";
      gtk-tabs-location = "bottom";
      clipboard-read = "allow";
      clipboard-paste-protection = false;
      shell-integration = "zsh";
    };
  };
}
