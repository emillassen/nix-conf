# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ inputs, outputs, lib, config, pkgs, nixpkgs-unstable, ... }:

{
  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default

    # You can also split up your configuration and import pieces of it here:
    ./config/git.nix # Needed for home-manager to work
    ./config/kitty.nix
    ./config/nvim.nix
    ./config/zsh/zsh.nix
    #./config/gnome/gnomesettings.nix
    #./config/gnome/catppuccin.nix # Broken atm
    #./config/nextcloud.nix # Broken in gnome
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default
    
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
      # Workaround for https://github.com/nix-community/home-manager/issues/2942
      allowUnfreePredicate = _: true;
    };
  };

  home = {
    username = "emil";
    homeDirectory = "/home/emil";
    sessionVariables = {
      VISUAL = "nvim";
      EDITOR = "nvim";
    };
  };

  home.packages = with pkgs; [
    unstable.curl
    unstable.wget
    unstable.micro
    bat
    bottom
    duf
    pciutils
    usbutils
    unstable.amdgpu_top
    unstable.fastfetch
    firefox
    wl-clipboard
    unstable.chromium
    mpv
    unstable.nextcloud-client
    gnome.gnome-tweaks
    gnome-extension-manager
    easyeffects
    unstable.vscodium
    libation
    thunderbird
    discord
    unstable.spotify
    yt-dlp
    handbrake
    unstable.mediainfo-gui
    unstable.mkvtoolnix
    filebot
    unstable.calibre
    caprine-bin
    libreoffice
    yacreader
    remmina
    wireguard-tools
    unstable.pupdate
   (pkgs.nerdfonts.override { fonts = [ "Hack" ]; })
    lazygit  # Enable git and basic config
    wirelesstools
    iw
    wavemon
    iperf
    unstable.ventoy-full
    whois
    unstable.stress-ng
    unstable.s-tui
    unstable.ollama
    #kdeconnect or gsconnect
    #dunst
    #cliphist
    #fuzzel
  ];

  # Required to autoload fonts from packages installed via Home Manager
  fonts.fontconfig.enable = true; 

  # Enable home-manager (git also required)
  programs.home-manager.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.11";
}
