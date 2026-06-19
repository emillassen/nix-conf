{
  pkgs,
  ...
}:
{
  # Packages managed directly in the environment
  environment.systemPackages = with pkgs; [
    gnupg # GNU Privacy Guard
  ];

  # Centralized configuration for programs
  programs = {
    # Enables yubikey-manager, pcscd, and necessary udev rules
    yubikey-manager.enable = true;

    # YubiKey touch notification service
    yubikey-touch-detector = {
      enable = true;
      libnotify = true; # Show desktop notifications
    };

    # GnuPG agent setup
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      # Qt-based PIN entry dialog (matches the Plasma desktop).
      pinentryPackage = pkgs.pinentry-qt;
    };
  };
}
