{ pkgs, ... }:
{
  programs.kitty = {
    enable = true;
    package = pkgs.kitty;
    font.name = "Hack Nerd Font Mono";
    font.size = 10.0;
    themeFile = "Catppuccin-Mocha";
    settings = {
      term = "xterm-kitty";
      cursor = "none";
      cursor_shape = "block";
      scrollback_lines = 100000;
      enable_audio_bell = "no";
      update_check_interval = 0;
      remember_window_size = "no";
      initial_window_width = "112c";
      initial_window_height = "70c";
      window_margin_width = "0";
      window_padding_width = "0";
      enabled_layouts = "horizontal";
      tab_bar_style = "powerline";
      tab_bar_min_tabs = 2;
      tab_powerline_style = "slanted";
      #background_opacity = "1.0";
      #background_blur = 1;
      #dynamic_background_opacity = "yes";
      #wayland_titlebar_color = "system";
    };
  };
}
