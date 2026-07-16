# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  pkgs,
  ...
}:
{
  # You can import other home-manager modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/home-manager):
    # outputs.homeManagerModules.example

    # Or modules exported from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModules.default
    inputs.catppuccin.homeModules.catppuccin

    # You can also split up your configuration and import pieces of it here:
    ./config/git.nix # Needed for home-manager to work
    ./config/catppuccin.nix
    #./config/kitty.nix
    ./config/ghostty.nix
    ./config/nixvim.nix
    ./config/zsh/zsh.nix
    ./config/vscode.nix
    ./config/zed-editor.nix
    ./config/helix.nix
    ./config/games.nix
    #./config/gnome/gnomesettings.nix # Keeps resetting settings
    #./config/gnome/catppuccin.nix # Broken atm
    #./config/nextcloud.nix # Broken in gnome
  ];

  # Overlays and nixpkgs config (allowUnfree etc.) come from the system-level
  # nixpkgs instance — home-manager.useGlobalPkgs is enabled in
  # nixos/configuration.nix, so nixpkgs.* options must not be set here.

  home = {
    username = "emil";
    homeDirectory = "/home/emil";
    sessionVariables = {
      VISUAL = "nvim";
      EDITOR = "nvim";
      # NH_FLAKE is set system-wide via programs.nh.flake (nixos/configuration.nix)
    };
    enableNixpkgsReleaseCheck = false;
  };

  home.packages =
    with pkgs;
    [
      amdgpu_top # AMD GPU monitoring tool
      android-tools # Android SDK tools (adb, fastboot, etc.)
      ansible # IT automation and configuration management
      anydesk # Remote desktop application
      #bambu-studio # PC Software for BambuLab's 3D printers
      # bat, btop and lazygit are configured as programs in config/catppuccin.nix
      # so Catppuccin can theme them.
      bottom # System monitor (btm command)
      blisp # In-System-Programming (ISP) tool & library
      calibre # E-book management application
      chirp # Radio programming software
      chromium # Open-source web browser
      curl # Command-line tool for transferring data
      delfin # Jellyfin client
      discord # Voice and text chat application
      drtv-dl # Download DRTV series for Jellyfin via yt-dlp (from /nix-conf/pkgs)
      duf # Disk usage analyzer
      easyeffects # Audio effects for PipeWire
      fastfetch # System information tool
      # FreeCAD from the stable channel: same 1.1.1 today, but prebuilt in the
      # 26.05 cache — on fresh unstable revs its vtk/pdal dependency chain is
      # often not cached yet and takes hours to compile locally.
      stable.freecad # Opensource CAD
      ffmpeg # Multimedia framework for video/audio processing
      filebot # TV show and movie file renaming tool
      firefox # Web browser
      #gimp # Image editing software (disabled)
      inkscape # Vector graphics editor
      iperf # Network performance testing tool
      iw # Wireless configuration utility
      kcc # Kindle Comic Converter
      krita # Digital painting application
      #lgogdownloader # GOG.com game downloader
      libation # Audible audiobook manager
      libreoffice # Office suite
      mediainfo-gui # Media file information viewer
      mkvtoolnix # Matroska video tools
      mpv # Media player
      ncdu # Disk usage analyzer with ncurses interface
      nerd-fonts.hack # Hack font with programming symbols
      nextcloud-client # Nextcloud desktop sync client
      nix-prefetch # Prefetch any fetcher function call, e.g. a package source
      nvme-cli # NVM-Express user space tooling for Linux
      orca-slicer # G-code generator for 3D printers.
      pciutils # PCI utilities (lspci, etc.)
      pupdate # Pupdate tool
      remmina # Remote desktop client
      s-tui # Stress testing and monitoring tool
      sdrpp # Software-defined radio application
      signal-desktop # Signal messenger desktop client
      spotify # Music streaming service
      stress-ng # System stress testing tool
      usbutils # USB utilities (lsusb, etc.)
      vuescan # Scanner software (from /nix-conf/pkgs)
      wavemon # Wireless network monitoring tool
      wget # File downloader
      wireguard-tools # WireGuard VPN tools
      wirelesstools # Wireless networking tools
      wl-clipboard # Wayland clipboard utilities
      yacreader # Comic book reader
      yt-dlp # YouTube video downloader
    ]
    # AI coding agents, referenced directly from the flake's packages output as
    # upstream's README documents (built against its own pinned nixpkgs, so the
    # numtide binary cache applies). claude-code is declared in config/vscode.nix.
    ++ (with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
      opencode # Open source coding agent
      gemini-cli # Google Gemini CLI agent
    ]);

  # Required to autoload fonts from packages installed via Home Manager
  fonts.fontconfig.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "26.05";
}
