# System-wide Catppuccin theming via the catppuccin/nix flake.
# https://nix.catppuccin.com
{
  catppuccin = {
    # Global flavor used by every catppuccin target on this host.
    flavor = "mocha";
    enable = true;
    # Enroll system targets explicitly (sddm + tty below) rather than everything.
    autoEnable = false;

    # SDDM login screen (KDE Plasma uses SDDM, see ../kde.nix).
    sddm = {
      enable = true;
      # SDDM runs as its own user, so the theme has to be exposed system-wide.
      fontSize = "12";
    };

    # Virtual console / TTY colors.
    tty.enable = true;

    # Boot splash / LUKS password screen (boot.plymouth enabled in ../configuration.nix).
    # Uses the global flavor (mocha) above; this target has no accent option.
    plymouth.enable = true;
  };
}
