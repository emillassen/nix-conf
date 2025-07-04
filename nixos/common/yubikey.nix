{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    gnupg
    yubikey-manager
    yubikey-personalization
    yubikey-touch-detector
    libfido2
    pam_u2f
    pinentry
  ];

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
      ExecStart = "${pkgs.gnupg}/bin/gpg-connect-agent /bye";
    };
  };

  services.pcscd.enable = true;
}
