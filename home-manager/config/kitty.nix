{ pkgs, nixpkgs-unstable, ...}:

{
  programs.kitty = {
    enable = true;
    package = pkgs.unstable.kitty;
    font.name = "Hack Nerd Font Mono";
    font.size = 11.0;
    theme = "Catppuccin-Mocha";
    settings = {
      cursor = "none";
      cursor_shape = "block";
      scrollback_lines = 10000;
      enable_audio_bell = "no";
      update_check_interval = 0;
      remember_window_size = "no";
      initial_window_width = "100c";
      initial_window_height = "63c";
      enabled_layouts = "horizontal";
      tab_bar_style = "powerline";
      tab_bar_min_tabs = 2;
      tab_powerline_style = "slanted";
      #background_opacity = "0.9";
      #background_blur = 250;
      #dynamic_background_opacity = "yes";
      #wayland_titlebar_color = "system";
    };
  };
}
