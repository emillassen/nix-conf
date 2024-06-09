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
    #./config/gnome/gnomesettings.nix # Keeps resetting settings
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
    wirelesstools
    iw
    wavemon
    iperf
    wireguard-tools
    unstable.amdgpu_top
    unstable.fastfetch
    unstable.stress-ng
    unstable.s-tui
    unstable.ventoy-full
   (pkgs.nerdfonts.override { fonts = [ "Hack" ]; })
    gnome-extension-manager
    gnome.gnome-themes-extra
    gnome.gnome-tweaks
    wl-clipboard
    lazygit # Enable git and basic config
    firefox
    unstable.chromium
    unstable.vscodium
    remmina
    mpv
    unstable.delfin
    unstable.nextcloud-client
    easyeffects
    libation
    thunderbird
    discord
    unstable.spotify
    yt-dlp
    handbrake
    unstable.mediainfo-gui
    unstable.mkvtoolnix
    unstable.ffmpeg
    filebot
    unstable.calibre
    libreoffice
    unstable.krita
    unstable.inkscape
    yacreader
    unstable.pupdate
    unstable.ollama
    unstable.android-tools
    unstable.vcmi
    vuescan # from /nix-conf/pkgs
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
  home.stateVersion = "24.05";
}
