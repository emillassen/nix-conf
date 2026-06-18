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

# Enter dev shell (provides sops, age, plus the pre-commit hook packages)
nix develop

# Edit encrypted secrets (smb.yaml, system.yaml, luks.yaml)
sops secrets/smb.yaml

# Garbage collect
sudo nix-collect-garbage -d && nix-store --optimise
```

## Architecture

**flake.nix** is the entry point. It defines one NixOS configuration (`fw13`) that composes:

- `nixos/configuration.nix` — Main system config. Imports hardware config, disk layout, desktop environment, and common modules. Home Manager is imported here as a NixOS module (not standalone).
- `nixos/common/` — Shared system modules: `pipewire.nix` (audio), `sops.nix` (secrets), `yubikey.nix` (GPG/SSH auth), `cifs.nix` (NAS mounts), `steam.nix` (gaming).
- `nixos/kde.nix` / `nixos/gnome.nix` — Desktop environments (KDE is active; `gnome.nix` import is commented out in `configuration.nix`).
- `nixos/disks.nix` — Disko declarative disk layout (LUKS-encrypted ext4).

**home-manager/home.nix** is the Home Manager entry point for user `emil`. Per-application configs live in `home-manager/config/` (git, ghostty, kitty, nixvim, zsh, vscode, zed-editor, helix, games, nextcloud, and `gnome/` for GNOME settings + Catppuccin). Several imports are currently disabled in `home.nix` (kitty, the `gnome/` configs, and nextcloud — see comments marking them as broken/resetting).

**Modules** (`modules/nixos/`, `modules/home-manager/`) are placeholder stubs for reusable modules you might export — both are currently empty.

**Overlays** (`overlays/default.nix`) provide a `stable` package set from nixpkgs-stable (`pkgs.stable`), an `additions` overlay that pulls in everything from `pkgs/`, and an (empty) `modifications` overlay for package overrides/patches.

**Custom packages** live in `pkgs/` — `vuescan` (scanner software) and `devilutionx` (Diablo engine, built from a pinned upstream commit). `pkgs/default.nix` wires them up; `pkgs/devilutionx/update.sh` refreshes the pinned revision.

**Secrets** in `secrets/` are SOPS-encrypted with age: `smb.yaml` (NAS/CIFS credentials), `system.yaml` (`emil` password hash), and `luks.yaml` (LUKS key). The age key lives at `~/.config/sops/age/keys.txt`; secret declarations live in `nixos/common/sops.nix`. Decrypted secrets mount to `/run/secrets/` at boot. `.sops.yaml` holds the age recipient and per-file creation rules.

**Bootstrap scripts** in `scripts/` pull credentials from Bitwarden during install: `pre-install-secrets.sh` (fetches the age key) and `setup-yubikey.sh` (provisions YubiKey material). These require the `bw` CLI.

## CI/CD

Three GitHub Actions workflows in `.github/workflows/`:

- **`ci.yml`** — Runs on push to `main`, PRs, and manual dispatch. Two parallel jobs: `checks` (flake-checker + `nix flake check`) and `build` (builds the `fw13` NixOS configuration).
- **`update-flake.yml`** — Weekly (Sunday midnight UTC) or manual. Runs `nix flake update` and opens a PR via `update-flake-lock`. Uses a PAT (`GH_TOKEN_FOR_UPDATES`) to trigger CI on the PR.
- **`update-devilutionx.yml`** — Weekly (Sunday midnight UTC) or manual. Checks upstream `diasurgical/devilutionX` for a new `master` commit, re-prefetches the hash, rewrites `pkgs/devilutionx/default.nix`, and opens a PR.

Actions used: `determinate-nix-action@v3` (Nix installation), `magic-nix-cache-action@v14` (GHA caching, FlakeHub disabled), `flake-checker-action@v12` (nixpkgs input health), `update-flake-lock@v28` (automated flake PRs), `peter-evans/create-pull-request@v8` (devilutionx PRs).

## Key Patterns

- The flake uses `nixpkgs-unstable` as the primary channel with `nixpkgs-stable` (26.05) available via `pkgs.stable` overlay.
- Pre-commit hooks are configured in the flake: nixfmt, statix, deadnix, prettier, sops encryption validation.
- Catppuccin Mocha is the system-wide theme (editors, terminal, git delta).
- User is `emil`, home at `/home/emil`. Zsh is the default shell.
- The `NH_FLAKE` environment variable is set to this repo path for the `nh` CLI tool.
