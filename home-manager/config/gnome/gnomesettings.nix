_: {
  # https://hoverbear.org/blog/declarative-gnome-configuration-in-nixos/
  # Use `dconf watch /` to track stateful changes you are doing, then set them here.
  # Values must use the proper Nix types (bool/float/etc.) so they marshal to the
  # matching GVariant types — strings like "true" or "0.1" are silently rejected
  # by dconf and the setting falls back to its default.
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      # Enables dark mode
      color-scheme = "prefer-dark";
      # Shows the exact charge level in the top bar
      show-battery-percentage = true;
      # Changes the text scaling factor to 1.25
      text-scaling-factor = 1.25;
    };
    "org/gnome/desktop/peripherals/touchpad" = {
      # Sets Touchpad speed
      speed = 0.1;
      # Enables tap to click using the trackpad
      tap-to-click = true;
    };
    # Disables mouse acceleration
    "org/gnome/desktop/peripherals/mouse" = {
      accel-profile = "flat";
    };
    # Enables fractional scaling in Gnome Settings -> Displays
    "org/gnome/mutter" = {
      experimental-features = [ "scale-monitor-framebuffer" ];
    };
    "org/gnome/settings-daemon/plugins/power" = {
      # Disables automatic screen brightness in Gnome Settings -> Power
      ambient-enabled = false;
      # Disables dimming of screen in Gnome Settings -> Power
      idle-dim = false;
    };
  };
}
