# Catppuccin theming for Home Manager via the catppuccin/nix flake.
# https://nix.catppuccin.com
#
# `catppuccin.enable` turns on theming for every supported program that is
# enabled in this Home Manager config (bat, btop, lazygit, delta, ghostty,
# helix, zsh-syntax-highlighting, ...). Each program's own `theme`/colorscheme
# option is set by the module, so those are no longer set by hand elsewhere.
{ pkgs, ... }:
{
  catppuccin = {
    enable = true;
    # Auto-enroll every supported program that is enabled below / elsewhere.
    autoEnable = true;
    flavor = "mocha";
  };

  # Enable a few programs as Home Manager modules (instead of bare packages)
  # so Catppuccin can theme them.
  programs = {
    bat.enable = true;

    btop = {
      enable = true;
      # Keep AMD GPU monitoring support.
      package = pkgs.btop.override { rocmSupport = true; };
    };

    lazygit.enable = true;
  };
}
