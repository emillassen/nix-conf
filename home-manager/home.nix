# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  nixpkgs-stable,
  ...
}: {
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
      outputs.overlays.stable-packages

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
    curl
    wget
    micro
    bat
    bottom
    duf
    ncdu
    pciutils
    usbutils
    wirelesstools
    iw
    wavemon
    iperf
    wireguard-tools
    amdgpu_top
    fastfetch
    stress-ng
    s-tui
    ventoy-full
    (pkgs.nerdfonts.override {fonts = ["Hack"];})
    #gnome-extension-manager
    #gnome-themes-extra
    #gnome-tweaks
    wl-clipboard
    lazygit # Enable git and basic config
    firefox
    chromium
    vscodium
    vscode-extensions.kamadorueda.alejandra
    alejandra
    remmina
    mpv
    delfin
    nextcloud-client
    easyeffects
    libation
    thunderbird
    discord
    spotify
    yt-dlp
    handbrake
    mediainfo-gui
    mkvtoolnix
    ffmpeg
    filebot
    calibre
    libreoffice
    krita
    inkscape
    yacreader
    pupdate
   # ollama
    android-tools
    vcmi
    vuescan # from /nix-conf/pkgs
    sdrpp
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
