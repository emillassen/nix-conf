# https://wiki.nixos.org/wiki/Steam
{ pkgs, ... }:
{
  fonts.fontconfig.cache32Bit = true;
  hardware.steam-hardware.enable = true;
  hardware.graphics.enable32Bit = true;
  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
      # Dedicated gamescope session selectable from the display manager.
      gamescopeSession.enable = true;
      # Proton-GE for better game/anti-cheat compatibility than stock Proton.
      extraCompatPackages = [ pkgs.proton-ge-bin ];
    };
    # CPU/GPU governor tuning when a game requests it (Feral GameMode).
    gamemode.enable = true;
  };
  services.pipewire.alsa.support32Bit = true;
}
