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
    ./config/ghostty.nix
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
      NH_FLAKE = "/home/emil/Documents/nix-conf";
    };
  };

  home.packages = with pkgs; [
    curl
    wget
    micro
    helix
    bat
    bottom
    (btop.override {rocmSupport = true;})
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
    #ventoy-full
    nerd-fonts.hack
    #gnome-extension-manager
    #gnome-themes-extra
    #gnome-tweaks
    wl-clipboard
    lazygit # Enable git and basic config
    ansible
    ansible-lint
    yamllint
    pre-commit
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
    kcc
    libreoffice
    lgogdownloader
    krita
    inkscape
    yacreader
    pupdate
    ollama
    android-tools
    vcmi
    vuescan # from /nix-conf/pkgs
    signal-desktop
    anydesk
    sdrpp
    chirp
    gimp
    #immich-cli
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
  home.stateVersion = "25.05";
}
