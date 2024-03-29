{ config, ... }:

{
  # https://hoverbear.org/blog/declarative-gnome-configuration-in-nixos/
  # Use `dconf watch /` to track stateful changes you are doing, then set them here.
  dconf.settings = {
    # Disables automatic screen brightness in Gnome Settings -> Power 
    "org/gnome/settings-daemon/plugins/power" = {
      ambient-enabled = "false";
    };
    # Disables dimming of screen in Gnome Settings -> Power
    "org/gnome/settings-daemon/plugins/power" = {
      idle-dim = "false";
    };
    # Enables fractional scaling in Gnome Settings -> Displays
    "org/gnome/mutter" = {
      experimental-features = [ "scale-monitor-framebuffer" ];
    };
    # Enables tap to click using the trackpad
    "org/gnome/desktop/peripherals/touchpad" = {
      tap-to-click = "true";
    };
    # Enables dark mode
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
    # Sets Touchpad speed
    "org/gnome/desktop/peripherals/touchpad" = {
      speed = "0.1";
    };
    # Disables mouse acceleration
    "org/gnome/desktop/peripherals/mouse" = {
      accel-profile = "flat";
    };
}
