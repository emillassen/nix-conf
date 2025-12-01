# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}:
{
  # You can import other NixOS modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/nixos):
    # outputs.nixosModules.example

    # Or modules from other flakes (such as nixos-hardware):
    inputs.home-manager.nixosModules.home-manager

    # You can also split up your configuration and import pieces of it here:
    ./hardware-configuration.nix
    ./disks.nix
    ./common/pipewire.nix
    #./gnome.nix # Uncomment this to use Gnome instead of KDE
    ./kde.nix
    ./common/steam.nix
    ./common/yubikey.nix
    ./common/sops.nix
    ./common/cifs.nix
  ];

  home-manager = {
    extraSpecialArgs = { inherit inputs outputs; };
    users = {
      emil = import ../home-manager/home.nix;
    };
  };

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
      allowUnfree = true;
    };
  };

  # Nix settings
  nix = {
    # Registry to make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: flake: { inherit flake; }) inputs;
    # Nix settings
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Disable 'warning : git tree 'nix-config folder' is dirty'
      warn-dirty = false;
      # Deduplicate and optimize nix store
      auto-optimise-store = true;
    };
  };

  # Sets Host Name for the device
  networking.hostName = "fw13";

  # Bootloader
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
      };
      efi.canTouchEfiVariables = true;
    };
    # Enable tmpfs for /tmp
    tmp = {
      useTmpfs = true;
      tmpfsSize = "16G"; # Adjust size as needed
    };
    # Enable latest linux kernel
    kernelPackages = pkgs.linuxPackages_latest;
  };

  # Enable zramswap
  #zramSwap.enable = true; # Disabled due to no swap on this host, have to reinstall first

  # Enables automatic upgrades
  #system.autoUpgrade.enable = true;
  #system.autoUpgrade.allowReboot = true;

  # NixOS simple statefull firewall blocks incoming connections and other unexpected packets. It's enabled by default.
  #networking.firewall.enable = false;

  # Enable networking
  networking.networkmanager.enable = true;

  # Enable Bluetooth
  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    # Enables RTL-SDR udev rules etc.
    rtl-sdr.enable = true;
  };

  # Services
  services = {
    # Enables firmware updates
    fwupd = {
      enable = true;
      #package = pkgs.fwupd;
      extraRemotes = [ "lvfs-testing" ];
    };
    # Enable fingerprint sensor
    fprintd.enable = true;
    # Enables Mullvad
    mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };
    # Configure keymap in X11
    xserver = {
      # Enable the X11 windowing system. Required for GNOME, KDE, Hyprland etc.
      enable = true;
      xkb = {
        layout = "dk";
        variant = "";
      };
    };
  };

  # Programs
  programs = {
    # Enables KDE Connect
    kdeconnect.enable = true;
    # Enable zsh
    zsh.enable = true;
    # Enable nh
    nh.enable = true;
  };

  # Packages to be installed systemwide
  #environment.systemPackages = with pkgs; [
  #];

  # Set your time zone
  time.timeZone = "Europe/Copenhagen";

  # Select internationalisation properties
  i18n.defaultLocale = "en_DK.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "da_DK.UTF-8";
    LC_IDENTIFICATION = "da_DK.UTF-8";
    LC_MEASUREMENT = "da_DK.UTF-8";
    LC_MONETARY = "da_DK.UTF-8";
    LC_NAME = "da_DK.UTF-8";
    LC_NUMERIC = "da_DK.UTF-8";
    LC_PAPER = "da_DK.UTF-8";
    LC_TELEPHONE = "da_DK.UTF-8";
    LC_TIME = "da_DK.UTF-8";
  };

  # Configure console keymap
  console.keyMap = "dk-latin1";

  # Defines users, groups etc.
  users.users = {
    emil = {
      isNormalUser = true;
      description = "Emil Lassen";
      # Password hash managed by sops-nix
      hashedPasswordFile = config.sops.secrets.emil_password_hash.path;
      extraGroups = [
        "networkmanager"
        "wheel"
        "dialout"
        "plugdev"
      ];
      shell = pkgs.zsh;
    };
  };

  # Cleans up generations every week
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.11";
}
