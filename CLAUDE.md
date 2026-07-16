# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A NixOS flake configuration for a Framework 13 7040 AMD laptop (host `fw13`, 32GB RAM, Radeon 780M iGPU), running KDE Plasma 6 on Wayland. Single host, single user (`emil`, zsh, home at `/home/emil`). Home Manager is integrated as a NixOS module, shares the system nixpkgs instance (`home-manager.useGlobalPkgs = true`), and installs `home.packages` through the system closure at `/etc/profiles/per-user/emil` (`useUserPackages = true` — not the mutable `~/.nix-profile`, whose GC root `nh clean` 4.4.0 deletes, nh issue #722). `README.md` has a feature overview.

## Build and Development Commands

```bash
# Rebuild and switch (nh is enabled; NH_FLAKE is set system-wide via programs.nh.flake)
nh os switch

# The standard way
sudo nixos-rebuild switch --flake /home/emil/Documents/nix-conf#fw13

# Format all Nix files. The formatter is nixfmt-tree (treefmt+nixfmt), which walks
# the tree itself — plain nixfmt breaks under `nix fmt` on Nix >= 2.25.
nix fmt

# Main validation gate: pre-commit hooks + full evaluation of the fw13 system.
# CI is disabled (see below), so always run this locally before committing.
nix flake check -v

# Update flake inputs
nix flake update

# Dev shell: sops, age, pre-commit tooling (also installs the git hooks)
nix develop

# Edit encrypted secrets (smb.yaml, system.yaml, luks.yaml)
sops secrets/smb.yaml

# Store/generation cleanup is automated (programs.nh.clean: --keep-since 30d --keep 10);
# manual equivalent:
nh clean all

# Custom packages can be built directly
nix build .#devilutionx
```

Zsh abbreviations on the host: `ns`/`nsu` (rebuild/upgrade), `nix-clean`, `flake-up`.

## Architecture

**flake.nix** is the entry point. Outputs: `nixosConfigurations.fw13`, `packages` (from `pkgs/`), `formatter` (nixfmt-tree), `overlays`, `devShells`, `checks` (pre-commit), plus empty `nixosModules`/`homeManagerModules` stubs (`modules/` is placeholder). `systems` is Linux-only (x86_64 + aarch64).

Inputs: nixpkgs (nixos-unstable), nixpkgs-stable (26.05), disko, home-manager, nixos-hardware, nix-vscode-extensions, sops-nix, pre-commit-hooks, nixvim, catppuccin, llm-agents. Every input follows the main nixpkgs **except `llm-agents`**, which keeps its own pinned nixpkgs on purpose so the numtide binary cache applies — do not add `follows` to it.

- `nixos/configuration.nix` — Main system config. Imports hardware config, disks, KDE, and the `common/` modules, and wires in Home Manager. All nixpkgs overlays and config (allowUnfree) live **here** and serve both system and HM: `additions` (pkgs/), `modifications` (empty), `stable-packages` (`pkgs.stable`), `nix-vscode-extensions` (`pkgs.vscode-marketplace.*`). The AI agents are deliberately not an overlay: they are referenced directly as `inputs.llm-agents.packages.<system>.*` (in `home.nix` and `config/vscode.nix`), the pattern upstream's README documents, so the numtide cache applies.
- `nixos/common/` — `pipewire.nix` (audio), `sops.nix` (secrets, see below), `yubikey.nix` (GPG agent + SSH support, yubikey-manager, touch detector), `cifs.nix` (NAS automounts at `/mnt/<share>` from 192.168.1.30, credentials via a sops template), `steam.nix` (+ gamemode, proton-ge), `catppuccin.nix` (system theming: SDDM, TTY, Plymouth).
- `nixos/kde.nix` — active desktop (Plasma 6, SDDM on Wayland, autologin). `nixos/gnome.nix` exists but its import is commented out in `configuration.nix`.
- `nixos/disks.nix` — Disko layout: GPT, 2G ESP, LUKS (`crypted`, discards allowed) with ext4 root. `passwordFile = /tmp/secret.key` is only used at install time.
- System notables: systemd initrd + Plymouth (themed LUKS prompt, `password-echo=no`), latest kernel, zram swap, tmpfs `/tmp` (16G), systemd-boot capped at 10 generations, fwupd (+ lvfs-testing), fprintd, Mullvad, fw-fanctrl, rtl-sdr, Danish locale and `dk`/`nodeadkeys` layout. `system.stateVersion = "26.05"` — do not bump it.

**home-manager/home.nix** is the HM entry point for `emil`. Per-app configs in `home-manager/config/`: git (+ delta, gh, GPG signing), catppuccin, ghostty, nixvim, zsh (+ starship, zsh-abbr), vscode, zed-editor, helix, games. Disabled imports (see comments in `home.nix`): `kitty.nix`, `gnome/gnomesettings.nix`, `gnome/catppuccin.nix`, `nextcloud.nix` — the gnome ones are moot under KDE but kept valid.

**pkgs/** — custom packages, exposed via the `additions` overlay and the `packages` output:

- `drtv-dl` — yt-dlp wrapper downloading DRTV series/seasons/films with Jellyfin naming (`Series/Season 01/Series - S01E01 - Title.ext`); carries a yt-dlp patch (`DRTVSeasonIE` entries `url` → `url_transparent` so series/season metadata reaches the output template, plus show descriptions/poster images surfaced on playlist results), and skips videos already on disk via a throwaway `--download-archive` (episodes found by a flat playlist scan; films and `-r` rechecks by a `--skip-download` probe that also refreshes their sidecars), so existing files are never rewritten by the metadata/subtitle embed. Generates Jellyfin sidecars as it goes: `tvshow.nfo` + poster/season posters per series, `.nfo` + thumb per episode, `.nfo` + poster per film — all with `<lockdata>true</lockdata>` so Jellyfin keeps DR's metadata instead of mismatching via TVDB/TMDB (`-r` backfills them for an existing library; the info.json→NFO conversion is jq in the script). Reads URLs from a `drtv-series.txt` in the library root when given none.
- `vuescan` — unfree scanner binary fetched from a personal mirror (github.com/emillassen/binary-mirror releases), autoPatchelf'd; the release tag/URL interpolates `version`.
- `devilutionx` — built from a pinned upstream master commit with vendored dependency pins (`FETCHCONTENT_SOURCE_DIR_*`); refresh with `pkgs/devilutionx/update.sh`.

## Secrets (sops-nix + age)

- `.sops.yaml` — single age recipient and per-file creation rules. The age key lives at `~/.config/sops/age/keys.txt` (`generateKey = false`; fetched from Bitwarden at install time by `scripts/pre-install-secrets.sh`; `scripts/setup-yubikey.sh` provisions YubiKey material — both need the `bw` CLI).
- `smb.yaml` → `smb_username`/`smb_password`, decrypted to `/run/secrets/`, consumed through a sops template as CIFS credentials.
- `system.yaml` → `emil_password_hash` (`neededForUsers = true`), decrypted to `/run/secrets-for-users/`.
- `luks.yaml` → LUKS key, **intentionally not declared** in `sops.nix`: it is only used at install time by disko, so it never lands on the running system.
- A `sops-secrets-validation` oneshot service checks at boot that secrets are readable; paths are derived from `config.sops.secrets.<name>.path` (the location differs for `neededForUsers` secrets).
- The `sops-encrypted` pre-commit hook blocks committing unencrypted files under `secrets/`. More detail in `secrets/README.md`.

## CI/CD — present but intentionally disabled

Three workflows exist in `.github/workflows/`, but **all three are manually disabled** — the owner doesn't use them currently. Do not assume CI validates anything, and do not re-enable them unless asked; local `nix flake check` is the gate.

- `ci.yml` — flake-checker + `nix flake check`, plus a full `fw13` toplevel build (push to main / PRs / dispatch).
- `update-flake.yml` — weekly `nix flake update` PR via update-flake-lock (PAT `GH_TOKEN_FOR_UPDATES`).
- `update-devilutionx.yml` — weekly upstream check; prefetches via `nix run nixpkgs#nix-prefetch-github` (with pipefail and an empty-hash guard), rewrites `pkgs/devilutionx/default.nix`, opens a PR.

Actions used: checkout@v7, determinate-nix-action@v3, magic-nix-cache-action@v14 (FlakeHub off), flake-checker-action@v12, update-flake-lock@v28, peter-evans/create-pull-request@v8.

## Key Patterns & Gotchas

- **Never set `nixpkgs.*` options (overlays/config) inside Home Manager modules** — with `useGlobalPkgs` that is a hard eval error. Add overlays in `nixos/configuration.nix` instead.
- Catppuccin Mocha comes from the catppuccin flake. HM sets `autoEnable = true`, so every enabled HM program is themed automatically — don't set per-app themes by hand (bat/btop/lazygit are enabled as HM programs precisely so they get themed). System targets (SDDM/TTY/Plymouth) are enrolled explicitly with `autoEnable = false`.
- nixvim deliberately evaluates its own nixpkgs instance (`programs.nixvim.nixpkgs.source = inputs.nixpkgs`).
- dconf values in `gnome/gnomesettings.nix` must be real Nix types (bool/float) — strings like `"true"` are rejected by GSettings and silently fall back to defaults.
- Pre-commit hooks (defined in flake.nix, run by `nix flake check` and on commit): nixfmt, statix, deadnix, prettier (yaml/markdown, excluding `secrets/`), sops-encrypted, plus standard hygiene hooks. The root `.pre-commit-config.yaml` is a gitignored symlink generated by the dev shell.
- Git: commits are GPG-signed by default (key on a YubiKey — a touch may be required). SSH remote operations also need the YubiKey; the `gh` CLI is authenticated and is the reliable path for GitHub API/HTTPS operations. Commit style: short imperative subject lines (see `git log`).
- `pkgs.stable` = nixpkgs 26.05; the primary channel is nixos-unstable.
