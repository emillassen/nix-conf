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

**flake.nix** is the entry point. Outputs: `nixosConfigurations.fw13`, `packages` (from `pkgs/`), `formatter` (nixfmt-tree), `overlays`, `devShells`, `checks` (pre-commit), plus empty `nixosModules`/`homeModules` stubs (`modules/` is placeholder; `homeModules` is the standard output name, not `homeManagerModules`). `systems` is Linux-only (x86_64 + aarch64).

Inputs: nixpkgs (nixos-unstable), nixpkgs-stable (26.05), disko, home-manager, nixos-hardware, nix-vscode-extensions, sops-nix, pre-commit-hooks (URL is `cachix/git-hooks.nix`, the renamed pre-commit-hooks.nix repo), nixvim, catppuccin, llm-agents. Every input follows the main nixpkgs **except `llm-agents`**, which keeps its own pinned nixpkgs on purpose so the numtide binary cache applies — do not add `follows` to it.

- `nixos/configuration.nix` — Main system config. Imports hardware config, disks, KDE, and the `common/` modules, and wires in Home Manager. All nixpkgs overlays and config (allowUnfree) live **here** and serve both system and HM: `additions` (pkgs/), `modifications` (currently just `filebot`: upstream ships no launcher, so the overlay extracts the app icons from `filebot.jar` and adds a desktop entry), `stable-packages` (`pkgs.stable`), `nix-vscode-extensions` (`pkgs.vscode-marketplace.*`). The AI agents are deliberately not an overlay: they are referenced directly as `inputs.llm-agents.packages.<system>.*` (in `home.nix` and `config/vscode.nix`), the pattern upstream's README documents, so the numtide cache applies.
- `nixos/common/` — `pipewire.nix` (audio), `sops.nix` (secrets, see below), `yubikey.nix` (GPG agent + SSH support, yubikey-manager, touch detector), `cifs.nix` (NAS automounts at `/mnt/<share>` from 192.168.1.30, credentials via a sops template), `steam.nix` (+ gamemode, proton-ge), `catppuccin.nix` (system theming: SDDM, TTY, Plymouth).
- `nixos/kde.nix` — active desktop (Plasma 6, SDDM on Wayland, autologin). `nixos/gnome.nix` exists but its import is commented out in `configuration.nix`.
- `nixos/disks.nix` — Disko layout: GPT, 2G ESP, LUKS (`crypted`, discards allowed) with ext4 root. `passwordFile = /tmp/secret.key` is only used at install time.
- System notables: systemd initrd + Plymouth (themed LUKS prompt, `password-echo=no`), latest kernel, zram swap, tmpfs `/tmp` (16G), systemd-boot capped at 10 generations, fwupd (+ lvfs-testing), fprintd, Mullvad, fw-fanctrl, rtl-sdr, Danish locale and `dk`/`nodeadkeys` layout. Flake-only Nix: `nix.channel.enable = false` (NIX_PATH/registry resolve to the flake's nixpkgs via `nixpkgs.flake.*` defaults) and scheduled `nix.optimise` instead of `auto-optimise-store`. `system.stateVersion = "26.05"` — do not bump it.

**home-manager/home.nix** is the HM entry point for `emil`. Per-app configs in `home-manager/config/`: git (+ delta, gh, GPG signing), catppuccin, ghostty, nixvim, zsh (+ starship, zsh-abbr), vscode, zed-editor, helix, games. Disabled imports (see comments in `home.nix`): `kitty.nix`, `gnome/gnomesettings.nix`, `gnome/catppuccin.nix`, `nextcloud.nix` — the gnome ones are moot under KDE but kept valid.

**pkgs/** — custom packages, exposed via the `additions` overlay and the `packages` output:

- `drtv-dl` — yt-dlp wrapper downloading DRTV series/seasons/films with Jellyfin naming (`Series/Season 01/Series - S01E01 - Title.ext`); carries a yt-dlp patch (`DRTVSeasonIE` entries `url` → `url_transparent` so series/season metadata reaches the output template, plus show descriptions/poster images surfaced on playlist results), and skips videos already on disk via a throwaway `--download-archive` (episodes found by a flat playlist scan; films and `-r` rechecks by a `--skip-download` probe that also refreshes their sidecars), so existing files are never rewritten by the metadata/subtitle embed. Generates Jellyfin sidecars as it goes: `tvshow.nfo` + poster/season posters per series, `.nfo` + thumb per episode, `.nfo` + poster per film — all with `<lockdata>true</lockdata>` so Jellyfin keeps DR's metadata instead of mismatching via TVDB/TMDB (the info.json→NFO conversion is jq in the script). The playlist scan classifies three ways, not two: video + `.nfo` present → download archive; video present, `.nfo` missing → handed to the `--skip-download` probe, so an ordinary run repairs sidecar gaps for the few episodes that have one instead of needing `-r` over everything (`scanned_bases` keeps the probe from counting those twice); nothing on disk → download. The thumbnail is deliberately not part of that test — DR has none for some videos, which would re-probe them forever. Progress is `[n/total] finished: path - N left, ~ETA`, the total being what both scans found missing before the run started. `-c` deletes yt-dlp's leftover scratch files (`.part`, `.part-Frag*`, `.ytdl`, per-format streams) from interrupted runs — every run reports what it finds, but only `-c` removes it, since a fragment may belong to a concurrent run. `-n` covers films too (one `--skip-download` probe each) and warns when a URL answers nothing, which is how DR taking a film down shows up. Reads URLs from a `drtv-series.txt` in the library root when given none.
- `standardebooks-dl` — pure-shell (curl + unzip) sync of a local Calibre-style library (`Last, First/Title/Title.{epub,azw3,kepub.epub,advanced.epub}` — one author directory, the epub's `file-as` sort name verbatim, same as Calibre's `{author_sort}`; an older `Last/First/Title` library is migrated in place on the next run, `-n` excepted — since the ledger otherwise keeps recreating legacy paths, the layout change alone would never reach books already synced) with the free ebooks at standardebooks.org. Enumerates the catalog from the site's `/sitemap` in one request, keeping only URLs ending in `/text` (the online reader) with the suffix stripped — the sitemap also lists ~2600 titles announced years ahead of their U.S. public-domain date, which have no files and used to cost a paced 404 probe every run; a published ebook has a `/text` subpage and a placeholder has none, and that filter was verified to reproduce all 31 pages of `/ebooks?per-page=48` exactly (1483 books). Author/title come from each epub's own `file-as` sort metadata, not the display name. A ledger (`DIR/.standardebooks-dl-index.tsv`) makes reruns incremental and resumable; it is a cache, not durable state — every SE epub carries its catalog URL as its OPF `dc:identifier` (translator segment included, so it _is_ the ledger's slug), so `rebuild_index` recovers the whole slug→path mapping from the epubs on disk, offline. That runs automatically when the ledger is missing/empty next to a non-empty library, and unconditionally under `-r`. Completeness is checked per format, not per folder (`media_count`/`media_exists` over all four extensions), and with `-s` rather than `-e` throughout, so a zero-byte file counts as missing instead of sticking forever. Lifts each book's embedded cover out as `cover.jpg` (path read from the epub's `cover-image` manifest item, so it's zero extra requests — Dolphin folder thumbnails + Calibre/Jellyfin artwork); `-r` backfills/repairs covers for an existing library straight from the local epubs (offline) and rebuilds the ledger in the same pass. Pacing is a quota ledger rather than a fixed delay (`quota_wait`/`quota_record` around every download, including the metadata probe): it mirrors the server's own algorithm — a timestamp per download the site actually served, in `${XDG_STATE_HOME:-~/.local/state}/standardebooks-dl/download-quota`, consulted before each request and slept against exactly (wait until the oldest ages out, never longer). It is keyed per machine, not per library, because the cap is per IP, and being on disk is the point: it survives restarts, where a fresh process would otherwise re-spend a budget already spent. `MIN_INTERVAL=30` only stops a whole window's budget going in a 90-second burst; the quota is the real constraint. A 429 now means the ledger disagrees with the server (lost ledger, browser downloads, shared NAT), so `fetch_url` waits it out with capped backoff for up to `LONG_WINDOW + 30m` instead of the old give-up-after-5-tries that marked good books failed — nothing can stay blocked longer than the 6h window, so outlasting it is the escape hatch. The old ≥8s/doubling-to-120s/never-recovering pacing was ~27x over the sustainable rate and assumed a penalty box that does not exist. A download 404 is still tolerated (counted as "no files offered", not a failure) for a book caught mid-publication or renamed since the sitemap was generated, but with the `/text` filter it should no longer happen routinely. A run surveys the whole catalog against disk before fetching anything (stat-only, no requests) to build the `todo` set, so it can report `[n/total] outcome: Author/Title - N left, ~ETA` per book — the ETA is elapsed-per-book extrapolated, and `todo` is also exactly what `-n` prints, so the two can't drift. Both `-n` and a real run also report files-to-fetch (counted per format, not per book), the resulting estimate (`files × 6h/100`) and current quota spend up front; `-n` lists both what's missing entirely and what's on disk but short a format (`slug (n/4 formats)`), without downloading.

  **SE's rate limit, measured 2026-07-30** (their site is open source — `standardebooks/web`, `www/ebooks/download.php` + `lib/Constants.php` — and live probing matched the source exactly). It applies **only to `/ebooks/*/downloads/*`**; `/sitemap`, catalog pages and book pages are unlimited (60 requests in 23s all returned 200, and kept returning 200 while downloads were blocked). Two sliding windows over _recorded_ downloads per IP: **more than 35 in 30s**, or **more than 100 in 6h** → 429 (`SHORT_DOWNLOAD_COUNT = 35`, `LONG_DOWNLOAD_COUNT = 100`, both compared with strict `>`). Verified: request 37 of an unpaced burst was the first 429, and with 74 already on the clock exactly 27 more succeeded before 429 at cumulative 101. There is **no penalty box** — a 429 is rejected before `AddDownload`, so it is never recorded and being blocked cannot extend the block; recovery is purely the window draining (measured 31.9s after a burst whose first request was at t=0.33s). The `RateLimitedIps` table an over-limit IP lands in only feeds `EbookDownload::IsBot()` for download _statistics_, it does not block. Logged-in (Patrons Circle) users skip the limiter entirely. Placeholders 404 _before_ the rate check, so probing them never cost quota — only wall-clock. **Sustained ceiling is therefore 100 files / 6h = 216s per file**, i.e. 14.4 min/book at 4 formats, so a full catalog sync is inherently ~2 weeks of wall time; the old 8s pace was ~27x over it, which is why a day-long run stalled. Probe the limiter with `curl -I` — HEAD runs `download.php` so it counts and 429s identically, but moves no file body.

  **Hazard:** a hidden `/honeypot` link in the site header is wired to fail2ban with `bantime = 24h, maxretry = 1` — a single GET firewall-bans the IP for 24 hours. Never follow SE links blindly; only construct download/catalog URLs.

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

Actions used: checkout@v7, determinate-nix-action@v3, magic-nix-cache-action@v14 (FlakeHub off), flake-checker-action@v13, update-flake-lock@v28, peter-evans/create-pull-request@v8. Renovate keeps these bumped.

## Key Patterns & Gotchas

- **Never set `nixpkgs.*` options (overlays/config) inside Home Manager modules** — with `useGlobalPkgs` that is a hard eval error. Add overlays in `nixos/configuration.nix` instead.
- Catppuccin Mocha comes from the catppuccin flake. HM sets `autoEnable = true`, so every enabled HM program is themed automatically — don't set per-app themes by hand (bat/btop/lazygit are enabled as HM programs precisely so they get themed). System targets (SDDM/TTY/Plymouth) are enrolled explicitly with `autoEnable = false`.
- nixvim deliberately evaluates its own nixpkgs instance (`programs.nixvim.nixpkgs.source = inputs.nixpkgs`).
- dconf values in `gnome/gnomesettings.nix` must be real Nix types (bool/float) — strings like `"true"` are rejected by GSettings and silently fall back to defaults.
- Pre-commit hooks (defined in flake.nix, run by `nix flake check` and on commit): nixfmt, statix, deadnix, prettier (yaml/markdown, excluding `secrets/`), sops-encrypted, plus standard hygiene hooks. The root `.pre-commit-config.yaml` is a gitignored symlink generated by the dev shell.
- Git: commits are GPG-signed by default (key on a YubiKey — a touch may be required). SSH remote operations also need the YubiKey; the `gh` CLI is authenticated and is the reliable path for GitHub API/HTTPS operations. Commit style: short imperative subject lines (see `git log`).
- `pkgs.stable` = nixpkgs 26.05; the primary channel is nixos-unstable.
