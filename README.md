# Emil's NixOS Configuration

My personal [NixOS](https://nixos.org/) configuration using [Nix Flakes](https://nixos.wiki/wiki/Flakes) and [Home Manager](https://github.com/nix-community/home-manager). It's built for my own hardware and workflow, but may be useful as a reference.

## System Overview

| Hostname |       Hardware        |      CPU       | RAM  |       GPU       | Desktop |
| :------: | :-------------------: | :------------: | :--: | :-------------: | :-----: |
|  `fw13`  | Framework 13 7040 AMD | AMD Ryzen 7040 | 32GB | AMD Radeon 780M |   KDE   |

## What's Set Up

Security and privacy:

- SOPS secrets management with age encryption
- YubiKey for GPG signing, SSH, and PAM auth
- LUKS-encrypted disk via Disko
- Firewall on by default
- Mullvad VPN

Desktop:

- KDE Plasma with Catppuccin Mocha theming (Wayland)
- GNOME config also present but disabled (`gnome.nix`)
- Framework 13 specific tweaks (fan control, fingerprint sensor)

Development:

- Zsh with Starship prompt
- Editors: Neovim (nixvim), Helix, VS Code, Zed
- Ghostty terminal (kitty config present but disabled)
- Pre-commit hooks (nixfmt, statix, deadnix, prettier, sops check)

Applications:

- Productivity: LibreOffice, Nextcloud
- Media: mpv, Spotify, Calibre, YACReader, drtv-dl (DRTV downloads with Jellyfin naming)
- Communication: Discord, Signal
- System monitoring: btop, fastfetch, s-tui

## Repository Structure

```
.
├── flake.nix                 # Main flake configuration
├── flake.lock                # Locked dependency versions
├── .sops.yaml                # SOPS configuration
├── home-manager/
│   ├── home.nix              # Home Manager entry point
│   └── config/               # Application configurations
│       ├── git.nix           # Git configuration
│       ├── zsh/              # Zsh and shell setup
│       ├── nixvim.nix        # Neovim configuration
│       ├── vscode.nix        # VS Code setup
│       └── gnome/            # GNOME-specific configs
├── nixos/
│   ├── configuration.nix     # Main NixOS configuration
│   ├── hardware-configuration.nix
│   ├── disks.nix             # Disko disk configuration
│   ├── kde.nix               # KDE Plasma setup
│   ├── gnome.nix             # GNOME setup
│   └── common/               # Shared configurations
│       ├── pipewire.nix      # Audio
│       ├── sops.nix          # Secrets
│       ├── yubikey.nix       # YubiKey
│       └── steam.nix         # Gaming
├── modules/                  # Reusable NixOS / Home Manager modules
├── overlays/default.nix      # Custom package overlays
├── pkgs/                     # Custom packages (drtv-dl, vuescan, devilutionx)
├── secrets/                  # Encrypted secrets (SOPS)
└── scripts/                  # Installation and setup scripts
```

## Installation

Prerequisites:

- Framework 13 7040 AMD (or compatible hardware)
- NixOS installation media
- Bitwarden account with the age key stored

### Fresh Installation

1. Boot from the NixOS USB and set up the environment:

   ```bash
   loadkeys dk   # keyboard layout, if needed
   nmtui         # connect to Wi-Fi
   ```

2. Clone the configuration:

   ```bash
   cd /tmp
   git clone https://github.com/emillassen/nix-conf.git
   cd nix-conf
   ```

3. Set up secrets (retrieves the age key from Bitwarden):

   ```bash
   ./scripts/pre-install-secrets.sh
   ```

4. Partition and format disks with Disko:

   ```bash
   sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko /tmp/nix-conf/nixos/disks.nix
   ```

5. Install NixOS:

   ```bash
   sudo nixos-install --root /mnt --flake /tmp/nix-conf#fw13 --no-root-passwd
   ```

6. Reboot and remove the USB drive.

### First Boot Setup

1. Connect to Wi-Fi and clone the repository:

   ```bash
   cd ~/Documents
   git clone https://github.com/emillassen/nix-conf.git
   cd ~/Documents/nix-conf
   git remote set-url origin git@github.com:emillassen/nix-conf.git
   ```

2. Enroll fingerprint:

   ```bash
   fprintd-enroll
   ```

3. Configure YubiKey (assumes a pre-configured YubiKey):

   ```bash
   ./scripts/setup-yubikey.sh
   ```

4. Apply the configuration:

   ```bash
   sudo nixos-rebuild switch
   ```

## Post-Install Configuration

### KDE Plasma

Configured manually after install:

1. System Settings:
   - Create KDE Wallet with empty password
   - Display → Scale → 125%
   - Display → Color Profile → Framework 13 ICC profile
   - Appearance → Colors → Catppuccin Mocha
   - Appearance → Icons → Papirus

2. System Tray:
   - Right-click battery → Show battery percentage

3. Input Devices:
   - Touchpad → Invert scroll direction
   - Touchpad → Two-finger right-click
   - Touchpad → Adjust scrolling speed

4. Window Management:
   - Virtual Desktops → Create 3 (Main, IT, Misc)
   - Window Behavior → Snap zones → 5px
   - Disable screen edge effects

### Display Color Profile

For accurate colors on the Framework 13:

1. Download the ICC profile from the [NotebookCheck review](https://www.notebookcheck.net/Framework-Laptop-13-5-Ryzen-7-7840U-review-So-much-better-than-the-Intel-version.756613.0.html).

2. Install it:

   ```bash
   cd ~/Downloads/
   colormgr import-profile BOE_CQ_______NE135FBM_N41_03.icm
   colormgr get-devices
   colormgr get-profiles
   colormgr device-add-profile <Device-ID> <Profile-ID>
   ```

3. Enable in System Settings → Display → Color Profile.

### Authentication

- GitHub: `gh auth login`
- Bitwarden: configure in browser
- Nextcloud: set up sync client
- Signal: link device
- VS Code: enable settings sync

## Security

### SOPS

Secrets are encrypted with SOPS and age:

- Age key: `~/.config/sops/age/keys.txt`
- Decrypted secrets mount to `/run/secrets/`
- Rendered templates (e.g. SMB credentials) under `/run/secrets/rendered/`

### YubiKey

Used for GPG signing, SSH authentication, and PAM. Run `./scripts/setup-yubikey.sh` to configure (requires a pre-configured YubiKey).

## Development

Pre-commit hooks: nixfmt, statix, deadnix, prettier, and a sops encryption check.

```bash
nix fmt                    # format all Nix files
nix flake check -v         # check flake (runs the hooks)
pre-commit run --all-files # run hooks manually
```

## CI/CD

Three GitHub Actions workflows in `.github/workflows/`:

- `ci.yml` — runs on push to `main`, PRs, and manual dispatch. Two parallel jobs: flake checks ([Flake Checker](https://github.com/DeterminateSystems/flake-checker-action) + `nix flake check`) and a full build of the `fw13` configuration. Uses [Determinate Nix](https://github.com/DeterminateSystems/determinate-nix-action) and [Magic Nix Cache](https://github.com/DeterminateSystems/magic-nix-cache-action).
- `update-flake.yml` — weekly (Sunday midnight UTC) or manual. Runs `nix flake update` and opens a PR via [update-flake-lock](https://github.com/DeterminateSystems/update-flake-lock).
- `update-devilutionx.yml` — weekly or manual. Checks upstream devilutionX for a new commit, re-prefetches the hash, and opens a PR.

## Troubleshooting

Secrets not decrypting:

```bash
ls -la ~/.config/sops/age/keys.txt   # check the age key exists
cd secrets && sops -d smb.yaml       # test manual decryption
```

## Resources

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [SOPS Documentation](https://github.com/mozilla/sops)
- [Framework 13 NixOS Guide](https://github.com/NixOS/nixos-hardware/tree/master/framework/13-inch/7040-amd)
- [Framework Community](https://community.frame.work/)
