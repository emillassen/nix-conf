{pkgs, ...}: {
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

  environment.shellInit = ''
    gpg-connect-agent /bye
    export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
  '';

  services.pcscd.enable = true;
}
