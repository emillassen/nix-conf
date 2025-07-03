_: {
  # https://hoverbear.org/blog/declarative-gnome-configuration-in-nixos/
  # Use `dconf watch /` to track stateful changes you are doing, then set them here.
  dconf.settings = {
    # Enables dark mode
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
    # Shows the excact charge level in the top bar
    "org/gnome/desktop/interface" = {
      show-battery-percentage = "true";
    };
    # Changes the text scaling factor to 1.25
    "org/gnome/desktop/interface" = {
      text-scaling-factor = "1.25";
    };
    # Sets Touchpad speed
    "org/gnome/desktop/peripherals/touchpad" = {
      speed = "0.1";
    };
    # Enables tap to click using the trackpad
    "org/gnome/desktop/peripherals/touchpad" = {
      tap-to-click = "true";
    };
    # Disables mouse acceleration
    "org/gnome/desktop/peripherals/mouse" = {
      accel-profile = "flat";
    };
    # Enables fractional scaling in Gnome Settings -> Displays
    "org/gnome/mutter" = {
      experimental-features = [ "scale-monitor-framebuffer" ];
    };
    # Disables automatic screen brightness in Gnome Settings -> Power
    "org/gnome/settings-daemon/plugins/power" = {
      ambient-enabled = "false";
    };
    # Disables dimming of screen in Gnome Settings -> Power
    "org/gnome/settings-daemon/plugins/power" = {
      idle-dim = "false";
    };
  };
}
