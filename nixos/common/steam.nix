# https://nixos.wiki/wiki/Steam
_: {
  fonts.fontconfig.cache32Bit = true;
  hardware.steam-hardware.enable = true;
  hardware.graphics.enable32Bit = true;
  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
    };
  };
  services.jack.alsa.support32Bit = true;
  services.pipewire.alsa.support32Bit = true;
}
