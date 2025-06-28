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
    #../modules/nixos/upgrade-diff.nix
    ./common/pipewire.nix
    #./gnome.nix
    ./kde.nix
    ./common/steam.nix
    ./common/yubikey.nix
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

  # This will add each flake input as a registry
  # To make nix3 commands consistent with your flake
  nix.registry = (lib.mapAttrs (_: flake: { inherit flake; })) (
    (lib.filterAttrs (_: lib.isType "flake")) inputs
  );

  # This will additionally add your inputs to the system's legacy channels
  # Making legacy nix commands consistent as well, awesome!
  nix.nixPath = [ "/etc/nix/path" ];
  environment.etc = lib.mapAttrs' (name: value: {
    name = "nix/path/${name}";
    value.source = value.flake;
  }) config.nix.registry;

  nix.settings = {
    experimental-features = "nix-command flakes";
    # Disable 'warning : git tree 'nix-config folder' is dirty'
    warn-dirty = false;
    # Deduplicate and optimize nix store
    auto-optimise-store = true;
  };

  # Sets Host Name for the device
  networking.hostName = "fw13";

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable tmpfs for /tmp
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "16G"; # Adjust size as needed

  # Enables automatic upgrades
  #system.autoUpgrade.enable = true;
  #system.autoUpgrade.allowReboot = true;

  # Enables firmware updates
  services.fwupd = {
    enable = true;
    #package = pkgs.fwupd;
    extraRemotes = [ "lvfs-testing" ];
  };

  # Enable latest linux kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable networking
  networking.networkmanager.enable = true;

  # Enable memtest86 in systemd-boot menu
  boot.loader.systemd-boot.memtest86.enable = true;

  # Enable Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Enable fingerprint sensor
  services.fprintd.enable = true;

  # Enables Mullvad
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };

  # Enables KDE Connect
  programs.kdeconnect.enable = true;

  # Enables RTL-SDR udev rules etc.
  hardware.rtl-sdr.enable = true;

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

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "dk";
    variant = "";
  };

  # Configure console keymap
  console.keyMap = "dk-latin1";

  # Enable zsh
  programs.zsh.enable = true;

  # Enable nh
  programs.nh.enable = true;

  # Enable the X11 windowing system. Required for GNOME, KDE, Hyprland etc.
  services.xserver.enable = true;

  # Defines users, groups etc.
  users.users = {
    emil = {
      isNormalUser = true;
      description = "Emil Lassen";
      # mkpasswd -m sha-512
      hashedPassword = "$6$DlWtQKGvf7B7Xb1h$r0mRQaLyvSWSf2VcvitX5uUIsHQoJfgNQDJcc30vtnh29WpZ1Xx0KMB7BJyTUGd0cntc2xdu4ZLd2KKyW/Pdc/";
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
  system.stateVersion = "25.05";
}
