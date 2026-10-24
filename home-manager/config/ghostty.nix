{ pkgs, ... }:
{
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty;
    settings = {
      #https://ghostty.org/docs/config/reference
      # theme is set by Catppuccin (config/catppuccin.nix)
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
      # A program asking for the clipboard (OSC 52, over SSH too) gets a prompt
      # rather than the contents: with "allow" anything in a terminal could read
      # a password copied from Bitwarden without a word.
      clipboard-read = "ask";
      clipboard-paste-protection = false;
      shell-integration = "zsh";
    };
  };
}
