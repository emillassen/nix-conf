# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A NixOS flake-based configuration for a Framework 13 7040 AMD laptop (host: `fw13`). Single-host setup with Home Manager integrated as a NixOS module.

## Build and Development Commands

```bash
# Rebuild and switch (nh is enabled, NH_FLAKE env var points here)
nh os switch

# Or the standard way
sudo nixos-rebuild switch --flake /home/emil/Documents/nix-conf#fw13

# Format all Nix files
nix fmt

# Run flake checks (pre-commit hooks + secrets validation)
nix flake check -v

# Update flake inputs
nix flake update

# Enter dev shell (provides sops, age, ssh-to-age)
nix develop

# Edit encrypted secrets
sops secrets/smb.yaml

# Garbage collect
sudo nix-collect-garbage -d && nix-store --optimise
```

## Architecture

**flake.nix** is the entry point. It defines one NixOS configuration (`fw13`) that composes:

- `nixos/configuration.nix` — Main system config. Imports hardware config, disk layout, desktop environment, and common modules. Home Manager is imported here as a NixOS module (not standalone).
- `nixos/common/` — Shared system modules: `pipewire.nix` (audio), `sops.nix` (secrets), `yubikey.nix` (GPG/SSH auth), `cifs.nix` (NAS mounts), `steam.nix` (gaming).
- `nixos/kde.nix` / `nixos/gnome.nix` — Desktop environments (KDE is active).
- `nixos/disks.nix` — Disko declarative disk layout (LUKS-encrypted ext4).

**home-manager/home.nix** is the Home Manager entry point for user `emil`. Per-application configs live in `home-manager/config/` (git, zsh, nixvim, vscode, ghostty, helix, zed-editor, games).

**Overlays** (`overlays/default.nix`) provide a `stable` package set from nixpkgs-stable and modifications/additions to nixpkgs.

**Custom packages** live in `pkgs/` (currently just vuescan).

**Secrets** in `secrets/` are SOPS-encrypted with age. The age key lives at `~/.config/sops/age/keys.txt`. Decrypted secrets mount to `/run/secrets/` at boot.

## Key Patterns

- The flake uses `nixpkgs-unstable` as the primary channel with `nixpkgs-stable` (25.11) available via `pkgs.stable` overlay.
- Pre-commit hooks are configured in the flake: nixfmt, statix, deadnix, prettier, sops encryption validation.
- Catppuccin Mocha is the system-wide theme (editors, terminal, git delta).
- User is `emil`, home at `/home/emil`. Zsh is the default shell.
- The `NH_FLAKE` environment variable is set to this repo path for the `nh` CLI tool.
