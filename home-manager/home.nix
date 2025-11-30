# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{ outputs, pkgs, ... }:
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
    ./config/ghostty.nix
    ./config/nvim.nix
    ./config/zsh/zsh.nix
    ./config/vscode.nix
    ./config/helix.nix
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
    amdgpu_top # AMD GPU monitoring tool
    android-tools # Android SDK tools (adb, fastboot, etc.)
    ansible # IT automation and configuration management
    anydesk # Remote desktop application
    bat # cat replacement with syntax highlighting
    bottom # System monitor (btm command)
    (btop.override {
      rocmSupport = true;
    }) # Interactive process viewer with AMD GPU support
    blisp # In-System-Programming (ISP) tool & library
    calibre # E-book management application
    chirp # Radio programming software
    chromium # Open-source web browser
    curl # Command-line tool for transferring data
    delfin # Jellyfin client
    discord # Voice and text chat application
    duf # Disk usage analyzer
    easyeffects # Audio effects for PipeWire
    fastfetch # System information tool
    ffmpeg # Multimedia framework for video/audio processing
    filebot # TV show and movie file renaming tool
    firefox # Web browser
    gemini-cli # Gemini protocol client
    #gimp # Image editing software (disabled)
    inkscape # Vector graphics editor
    iperf # Network performance testing tool
    iw # Wireless configuration utility
    kcc # Kindle Comic Converter
    krita # Digital painting application
    lazygit # Git terminal UI
    lgogdownloader # GOG.com game downloader
    libation # Audible audiobook manager
    libreoffice # Office suite
    mediainfo-gui # Media file information viewer
    mkvtoolnix # Matroska video tools
    mpv # Media player
    ncdu # Disk usage analyzer with ncurses interface
    nerd-fonts.hack # Hack font with programming symbols
    nextcloud-client # Nextcloud desktop sync client
    pciutils # PCI utilities (lspci, etc.)
    pupdate # Pupdate tool
    remmina # Remote desktop client
    s-tui # Stress testing and monitoring tool
    sdrpp # Software-defined radio application
    signal-desktop # Signal messenger desktop client
    spotify # Music streaming service
    stress-ng # System stress testing tool
    thunderbird # Email client
    usbutils # USB utilities (lsusb, etc.)
    vcmi # Heroes of Might and Magic 3 engine
    vuescan # Scanner software (from /nix-conf/pkgs)
    wavemon # Wireless network monitoring tool
    wget # File downloader
    wireguard-tools # WireGuard VPN tools
    wirelesstools # Wireless networking tools
    wl-clipboard # Wayland clipboard utilities
    yacreader # Comic book reader
    yt-dlp # YouTube video downloader
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
