{
  pkgs,
  config,
  lib,
  ...
}:
let
  gpg-connect-agent = lib.getExe' config.programs.gnupg.package "gpg-connect-agent";
  gpgconf = lib.getExe' config.programs.gnupg.package "gpgconf";
in
{
  environment.systemPackages = with pkgs; [
    yubikey-manager # YubiKey management tool and library
    yubikey-personalization # YubiKey personalization tool
    pinentry-qt # Qt-based PIN entry dialog (works best with KDE)
    gnupg # GNU Privacy Guard for encryption and signing
  ];

  # Detects whenever a YubiKey is waiting for your touch.
  programs.yubikey-touch-detector = {
    enable = true;
    libnotify = true; # Show desktop notifications using libnotify
  };

  services = {
    udev.packages = [ pkgs.yubikey-personalization ];
    pcscd.enable = true;
  };

  # Disabled since we aren't using yubikeys for user auths
  #security.pam.u2f.enable = true;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Initialize GPG agent once at login
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
