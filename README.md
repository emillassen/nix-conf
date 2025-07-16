<div align="center">

# Emil's NixOS Configuration

**A modern, secure NixOS setup with Flakes, Home Manager, and declarative system management**

_Made with ❄️ for productivity and security_

</div>

This repository contains my personal [NixOS](https://nixos.org/) configuration using [Nix Flakes](https://nixos.wiki/wiki/Flakes) and [Home Manager](https://github.com/nix-community/home-manager). It's designed for my specific workflow and hardware, but may serve as a reference or starting point for your own configuration.

## 🖥️ System Overview

| Hostname |       Hardware        |      CPU       | RAM  |       GPU       |  Desktop  | OS  | Status |
| :------: | :-------------------: | :------------: | :--: | :-------------: | :-------: | :-: | :----: |
|  `fw13`  | Framework 13 7040 AMD | AMD Ryzen 7040 | 32GB | AMD Radeon 780M | KDE/GNOME | ❄️  |   ✅   |

**Key:**

- 💻 Laptop
- ❄️ NixOS
- ✅ Active
- 🚧 Work in Progress

## ✨ Features

### 🔒 Security & Privacy

- **SOPS-based secrets management** with age encryption
- **YubiKey integration** for authentication
- **Encrypted disk** with LUKS via Disko
- **Firewall enabled** by default
- **Mullvad VPN** integration

### 🖥️ Desktop Environments

- **KDE Plasma** (primary) with Catppuccin theming
- **GNOME** (alternative) with declarative configuration
- **Wayland** support with proper hardware acceleration
- **Framework 13** specific optimizations

### 🛠️ Development Environment

- **Modern shell** with Zsh, Starship prompt
- **Multiple editors**: Neovim, Helix, VS Code
- **Development tools**: Git, Docker, Android tools
- **Terminal emulators**: Kitty, Ghostty
- **Pre-commit hooks** for code quality

### 📦 Application Suite

- **Productivity**: LibreOffice, Nextcloud, Thunderbird
- **Media**: mpv, Spotify, Calibre, YACReader
- **Communication**: Discord, Signal, Element
- **Development**: Multiple IDEs and CLI tools
- **System monitoring**: btop, fastfetch, s-tui

## 🏗️ Repository Structure

```
.
├── flake.nix                 # Main flake configuration
├── flake.lock               # Locked dependency versions
├── .sops.yaml               # SOPS configuration
├── home-manager/
│   ├── home.nix            # Home Manager entry point
│   └── config/             # Application configurations
│       ├── git.nix         # Git configuration
│       ├── zsh/            # Zsh and shell setup
│       ├── nvim.nix        # Neovim configuration
│       ├── vscode.nix      # VS Code setup
│       └── gnome/          # GNOME-specific configs
├── nixos/
│   ├── configuration.nix   # Main NixOS configuration
│   ├── hardware-configuration.nix  # Hardware-specific settings
│   ├── disks.nix           # Disko disk configuration
│   ├── kde.nix             # KDE Plasma setup
│   ├── gnome.nix           # GNOME setup
│   └── common/             # Shared configurations
│       ├── pipewire.nix    # Audio configuration
│       ├── sops.nix        # Secrets management
│       ├── yubikey.nix     # YubiKey integration
│       └── steam.nix       # Gaming setup
├── modules/
│   ├── nixos/              # Custom NixOS modules
│   └── home-manager/       # Custom Home Manager modules
├── overlays/
│   └── default.nix         # Custom package overlays
├── pkgs/
│   └── vuescan/            # Custom packages
├── secrets/                # Encrypted secrets (SOPS)
└── scripts/                # Installation and setup scripts
```

## 🚀 Installation

### Prerequisites

- Framework 13 7040 AMD (or compatible hardware)
- NixOS installation media
- Bitwarden account with age key stored

### Fresh Installation

1. **Boot from NixOS USB** and set up environment:

   ```bash
   # Change keyboard layout if needed
   loadkeys dk

   # Connect to Wi-Fi
   nmtui
   ```

2. **Clone and prepare configuration**:

   ```bash
   cd /tmp
   git clone https://github.com/emillassen/nix-conf.git
   cd nix-conf
   ```

3. **Set up secrets** (retrieves age key from Bitwarden):

   ```bash
   ./scripts/pre-install-secrets.sh
   ```

4. **Partition and format disks** using Disko:

   ```bash
   sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko /tmp/nix-conf/nixos/disks.nix
   ```

5. **Install NixOS**:

   ```bash
   sudo nixos-install --root /mnt --flake /tmp/nix-conf#fw13 --no-root-passwd
   ```

6. **Reboot** and remove USB drive

### First Boot Setup

1. **Connect to Wi-Fi** and clone repository:

   ```bash
   cd ~/Documents
   git clone https://github.com/emillassen/nix-conf.git
   cd ~/Documents/nix-conf
   git remote set-url origin git@github.com:emillassen/nix-conf.git
   ```

2. **Set up biometric authentication**:

   ```bash
   fprintd-enroll
   ```

3. **Configure YubiKey** (assumes pre-configured YubiKey):

   ```bash
   ./scripts/setup-yubikey.sh
   ```

4. **Apply final configuration**:
   ```bash
   sudo nixos-rebuild switch
   ```

## 🔧 Usage

### Applying Changes

The configuration lives in `~/Documents/nix-conf`. To apply changes:

```bash
cd ~/Documents/nix-conf

# Rebuild NixOS configuration
sudo nixos-rebuild switch

# Rebuild Home Manager configuration
home-manager switch --flake .
```

### Managing Secrets

This setup uses SOPS for secrets management:

```bash
# Edit secrets (automatically encrypts)
sops secrets/smb.yaml

# View secrets
sops -d secrets/smb.yaml

# Add new secrets file
echo "new_secret: value" > secrets/new-file.yaml
sops -e -i secrets/new-file.yaml
```

### Development Environment

A development shell is available with secrets management tools:

```bash
# Enter development shell
nix develop

# Available tools: sops, age, and more
```

## 🎨 Post-Install Configuration

### KDE Plasma Customization

After installation, manually configure KDE:

1. **System Settings**:

   - Create KDE Wallet with empty password
   - Display → Scale → 125%
   - Display → Color Profile → Framework 13 ICC profile
   - Appearance → Colors → Catppuccin Mocha
   - Appearance → Icons → Papirus

2. **System Tray**:

   - Right-click battery → Show battery percentage
   - Configure other applets as needed

3. **Input Devices**:

   - Touchpad → Invert scroll direction
   - Touchpad → Two-finger right-click
   - Touchpad → Adjust scrolling speed

4. **Window Management**:
   - Virtual Desktops → Create 3 (Main, IT, Misc)
   - Window Behavior → Snap zones → 5px
   - Disable screen edge effects

### Display Color Profile

For accurate colors on the Framework 13:

1. Download ICC profile from [NotebookCheck review](https://www.notebookcheck.net/Framework-Laptop-13-5-Ryzen-7-7840U-review-So-much-better-than-the-Intel-version.756613.0.html)

2. Install profile:

   ```bash
   cd ~/Downloads/
   colormgr import-profile BOE_CQ_______NE135FBM_N41_03.icm
   colormgr get-devices
   colormgr get-profiles
   colormgr device-add-profile <Device-ID> <Profile-ID>
   ```

3. Enable in System Settings → Display → Color Profile

### Authentication Setup

Complete authentication setup for various services:

- **GitHub**: `gh auth login`
- **Bitwarden**: Configure in browser
- **Nextcloud**: Set up sync client
- **Signal**: Link device
- **VS Code**: Enable settings sync

## 🔒 Security Features

### SOPS Integration

All secrets are encrypted using SOPS with age keys:

- **Age key location**: `~/.config/sops/age/keys.txt`
- **System secrets**: Mounted to `/run/secrets/`
- **Templates**: Rendered to `/run/secrets-rendered/`

### YubiKey Setup

YubiKey provides:

- **GPG signing** for Git commits
- **SSH authentication**
- **System authentication** (PAM)

Run `./scripts/setup-yubikey.sh` to configure (requires pre-configured YubiKey).

### Backup Strategy

Important items to backup:

- `~/.config/sops/age/keys.txt` (age private key)
- YubiKey recovery codes
- Bitwarden master password
- Git SSH keys

## 🛠️ Customization

### Adding Applications

1. **System-wide packages**: Add to `nixos/configuration.nix`
2. **User packages**: Add to `home-manager/home.nix`
3. **Custom packages**: Create in `pkgs/` directory

### Desktop Environment

Switch between desktop environments:

```bash
# Enable KDE (default)
# In nixos/configuration.nix: import ./kde.nix

# Enable GNOME
# In nixos/configuration.nix: import ./gnome.nix
```

### Custom Modules

Add reusable modules to:

- `modules/nixos/` for system-level modules
- `modules/home-manager/` for user-level modules

## 🤝 Development

### Pre-commit Hooks

This repository includes pre-commit hooks for:

- **Nix formatting** (nixfmt-rfc-style)
- **Linting** (statix, deadnix)
- **Secret validation** (sops encryption check)
- **File validation** (trailing whitespace, large files)

### Code Quality

```bash
# Format all Nix files
nix fmt

# Check flake
nix flake check

# Run pre-commit hooks manually
pre-commit run --all-files
```

## 📋 Troubleshooting

### Common Issues

**Secrets not decrypting**:

```bash
# Check age key exists
ls -la ~/.config/sops/age/keys.txt

# Test manual decryption
cd secrets && sops -d smb.yaml
```

**Build failures**:

```bash
# Clean build cache
sudo nix-collect-garbage -d

# Rebuild with verbose output
sudo nixos-rebuild switch --show-trace
```

**YubiKey not recognized**:

```bash
# Check YubiKey detection
ykman info

# Restart services
sudo systemctl restart pcscd
```

## 📚 Resources

### Documentation

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [SOPS Documentation](https://github.com/mozilla/sops)

### Hardware-Specific

- [Framework 13 NixOS Guide](https://github.com/NixOS/nixos-hardware/tree/master/framework/13-inch/7040-amd)
- [Framework Community](https://community.frame.work/)

---

_This configuration is tailored for my specific needs and hardware. Feel free to use it as inspiration, but don't expect it to work out-of-the-box on your system._
