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
    # Modules this flake exports (from modules/nixos) would go here:
    # outputs.nixosModules.example

    # Home Manager as a NixOS module (hardware/disko/sops/catppuccin modules
    # are wired up in flake.nix next to the host definition)
    inputs.home-manager.nixosModules.home-manager

    ./hardware-configuration.nix
    ./disks.nix
    ./common/pipewire.nix
    #./gnome.nix # Uncomment this to use Gnome instead of KDE
    ./kde.nix
    ./common/steam.nix
    ./common/yubikey.nix
    ./common/sops.nix
    ./common/cifs.nix
    ./common/catppuccin.nix
  ];

  home-manager = {
    # Reuse the system nixpkgs instance (with the overlays/config below) instead
    # of evaluating a second private instance — faster rebuilds, and one single
    # place (this file) for overlays and allowUnfree.
    useGlobalPkgs = true;
    # Install home.packages via users.users.emil.packages (/etc/profiles,
    # part of the system closure) instead of the nix-env profile at
    # ~/.nix-profile, whose GC root nh clean 4.4.0 deletes (nh issue #722).
    useUserPackages = true;
    # If HM starts managing a file that already exists on disk, rename the old
    # file to *.backup instead of aborting the whole system switch.
    backupFileExtension = "backup";
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

      # VSCode marketplace extensions -> pkgs.vscode-marketplace.*
      inputs.nix-vscode-extensions.overlays.default

      # The AI coding agents are intentionally NOT an overlay: per upstream's
      # README they are referenced directly from inputs.llm-agents.packages
      # (home.nix, vscode.nix), built against the flake's own pinned nixpkgs
      # so the numtide binary cache applies. Its overlays.shared-nixpkgs would
      # rebuild them against our nixpkgs and miss the cache.
    ];
    # Configure your nixpkgs instance
    config = {
      allowUnfree = true;
    };
  };

  # Nix settings
  nix = {
    # Flake-only system: disable the nix-channel machinery. <nixpkgs> and the
    # system flake registry still resolve to this flake's pinned input via the
    # nixpkgs.flake.setNixPath/setFlakeRegistry defaults.
    channel.enable = false;
    # Registry to make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: flake: { inherit flake; }) inputs;
    # Deduplicate the store on a schedule (idle priority, AC only, catches up
    # on missed runs) instead of hardlinking during every build —
    # auto-optimise-store slows builds (NixOS/nix#6033).
    optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Disable 'warning : git tree 'nix-config folder' is dirty'
      warn-dirty = false;
      # Lets emil pass extra substituters/keys from a flake's nixConfig
      # (e.g. this flake's own nixConfig at install time)
      trusted-users = [ "emil" ];
      # Mirror this flake's nixConfig caches system-wide so builds never depend
      # on flake-config acceptance (non-interactive runs like nh ignore it).
      extra-substituters = [
        "https://nix-community.cachix.org"
        "https://cache.numtide.com"
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
      # This flake's own nixConfig is the same set of caches — accept it
      # silently instead of warning on every nh/nixos-rebuild run.
      accept-flake-config = true;
    };
  };

  # Sets Host Name for the device
  networking.hostName = "fw13";

  # Bootloader
  boot = {
    loader = {
      timeout = 0;
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
        # Cap stored generations so the 2G ESP doesn't fill up with old kernels/initrds
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      # Use systemd in the initrd so Plymouth (and the themed LUKS prompt) start early
      systemd.enable = true;
      # Don't echo asterisks while typing the LUKS passphrase at boot
      # (password-echo: "yes" = show chars, "masked" = asterisks (default), "no" = nothing)
      luks.devices."crypted".crypttabExtraOpts = [ "password-echo=no" ];
      # Plymouth wants a quiet boot to look clean
      verbose = false;
    };
    # Graphical boot splash + LUKS password screen (themed via ./common/catppuccin.nix)
    plymouth.enable = true;
    consoleLogLevel = 0;
    kernelParams = [
      "quiet"
      "rd.udev.log_level=3"
      "rd.systemd.show_status=auto"
    ];
    # Enable tmpfs for /tmp
    tmp = {
      useTmpfs = true;
      tmpfsSize = "16G"; # Adjust size as needed
    };
    # Enable latest linux kernel
    kernelPackages = pkgs.linuxPackages_latest;
  };

  # Compressed RAM-backed swap (no disk partition required).
  zramSwap.enable = true;

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
    # Periodic TRIM for the SSD (LUKS allowDiscards is set in disks.nix)
    fstrim.enable = true;
    # Enables firmware updates
    fwupd = {
      enable = true;
      #package = pkgs.fwupd;
      extraRemotes = [ "lvfs-testing" ];
    };
    # Enable fingerprint sensor
    fprintd.enable = true;
    # Enables Mullvad
    mullvad-vpn.enable = true;
    # Keyboard layout. Plasma runs on Wayland (SDDM Wayland), so the full X
    # server isn't enabled; xkb here still feeds SDDM and the Plasma default.
    xserver.xkb = {
      layout = "dk";
      # nodeadkeys: ~ ` ^ ´ emit literally instead of acting as dead keys
      # (composing accents). Ghostty swallows dead-key sequences, so a bare
      # layout makes ~ untypable in the terminal.
      variant = "nodeadkeys";
    };
  };

  # Programs
  programs = {
    # Enables KDE Connect
    kdeconnect.enable = true;
    # Enable zsh
    zsh.enable = true;
    # Enable nh and let it handle store cleanup (store-aware GC).
    nh = {
      enable = true;
      # Sets the NH_FLAKE environment variable for all sessions.
      flake = "/home/emil/Documents/nix-conf";
      clean = {
        enable = true;
        extraArgs = "--keep-since 30d --keep 10";
      };
    };
  };

  # Framework 13 fan control
  hardware.fw-fanctrl.enable = true;

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

  # Generation cleanup is handled by programs.nh.clean (see above).

  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "26.05";
}
