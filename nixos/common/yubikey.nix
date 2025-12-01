{
  pkgs,
  config,
  lib,
  ...
}:
let
  # Determine the paths for gpg executables
  gpg-connect-agent = lib.getExe' config.programs.gnupg.package "gpg-connect-agent";
  gpgconf = lib.getExe' config.programs.gnupg.package "gpgconf";
in
{
  # Packages managed directly in the environment
  environment.systemPackages = with pkgs; [
    pinentry-qt # Qt-based PIN entry dialog
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
    };
  };

  # Initialize GPG agent once at login for SSH and GPG operations
  systemd.user.services.gpg-agent-init = {
    description = "Initialize GnuPG agent";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''
        ${gpg-connect-agent} /bye
        export SSH_AUTH_SOCK=$(${gpgconf} --list-dirs agent-ssh-socket)
      '';
    };
  };
}
