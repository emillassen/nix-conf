_: {
  # Enable the KDE Plasma Desktop Environment.
  services = {
    displayManager = {
      sddm = {
        enable = true;
        wayland.enable = true;
      };
      defaultSession = "plasma";
      autoLogin = {
        enable = true;
        user = "emil";
      };
    };
    desktopManager.plasma6.enable = true;
  };
}
