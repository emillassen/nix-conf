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

# Update them without breaking the build: search for the newest lock that still
# builds fw13, per input, and write that (zsh abbr `fus`). -n reports what has
# updates without building anything.
./scripts/flake-up-safe.sh

# Dev shell: sops, age, pre-commit tooling (also installs the git hooks)
nix develop

# Edit encrypted secrets (smb.yaml, system.yaml, luks.yaml)
sops secrets/smb.yaml

# Store/generation cleanup is automated (programs.nh.clean: --keep-since 30d --keep 10);
# manual equivalent:
nh clean all

# Custom packages can be built directly
nix build .#devilutionx

# The shell test suite: hermetic, offline, no network and no Nix daemon.
# Takes ~30s. Not wired into `nix flake check` - run it by hand.
./tests/run.sh                 # everything
./tests/run.sh flake-up-safe   # only cases whose path matches
KEEP_TMP=1 ./tests/run.sh drtv/04   # leave the case's temp dir behind

# The other half of that: build the two pkgs/ derivations for real (which is
# where shellcheck runs for them) and run each one's -h.
./tests/build-check.sh
```

Zsh abbreviations on the host: `ns`/`nsu` (rebuild/upgrade), `nix-clean`, `flake-up`, `fus`.

`scripts/flake-up-safe.sh` keeps the lock as new as it can be while still building. It
takes the committed lock as a known-good baseline and tries all inputs at their tips; a
set that fails is split in half and each half retried on top of whatever has already been
accepted, so one culprit among eleven inputs costs about seven trials instead of eleven,
and an input that only breaks in combination with another is still caught (every trial is
"what we kept so far, plus this half" — there is no separate combine pass). The inputs
left behind are then bisected through their own history for the newest revision that does
build, and pinned with `nix flake lock --override-input` — which moves only `locked`, so a
later plain `nix flake update` still follows the branch. The pin is read back out of the
lock afterwards, because `--override-input` implying `--no-write-lock-file` has been
proposed upstream more than once and every verdict after it would silently be a verdict on
the unpinned lock. `--no-bisect` settles for baseline-or-tip instead.

Where the bisect's candidates come from depends on the input. For a **nixpkgs input that
tracks a channel** they are the channel's own releases, listed from the `nix-releases` S3
bucket (`?prefix=nixos/unstable/&delimiter=/`, one request; the directory names carry a
short rev and a serial, and the full rev comes from each release's `git-revision` file).
The listing starts at a `marker`, since `nixos/unstable/` holds a decade of releases: for a
stable channel that marker is exact (every `nixos-25.05.*` release names its own channel),
and only for a rolling channel is it guessed from the tip's calendar year, whose version
number the name tracks. Guessing for a stable channel too used to skip its whole listing
once the channel was over a year old, silently dropping the run back to a commit search.
That matters because the branch's git history is mostly master commits the channel never
pointed at, and only a channel bump has passed Hydra's `tested` job — bisecting to an
arbitrary commit would lock in a revision cache.nixos.org has barely built, i.e. a local
rebuild of the world. The bucket lists lexicographically, which is _not_ chronological
(`nixos-26.05.889` sorts after `nixos-26.05.7675`), so ordering comes from the serial in
the name, which is a commit count and only goes up. Everything else falls back to one
candidate per day, newest first, resolved through the GitHub API (`gh`, else curl) against
the **tip's own history** rather than the branch, so a branch moving mid-run cannot change
what is being searched. A search in which every one of those lookups failed reports that
it could not resolve anything, distinctly from "nothing newer builds": an unreachable or
rate-limited GitHub is not a verdict on the input, and nothing was built for it. Index 0
of either list is the tip itself: it was rejected on top of a smaller set of updates than
the one now in force, so it is worth re-testing, and if nothing changed since, the `.drv`
cache answers for free.

The search itself walks newest-first and checks the first `--linear` candidates (default 7)
**one at a time**, then starts doubling its stride and binary-searches the bracket that
straddles the boundary. `--linear N` means exactly N candidates, counted in probes made:
counting the index reached instead left the stride at 1 for one step longer than asked, so
the prefix was N+1 and `--linear 0` still checked two, with no way to ask for no prefix at
all (`tests/cases/flake-up-safe/11-linear-walk-table.sh` pins the whole walk). The linear
prefix needs no assumptions — everything newer has been tried and failed, so the first
candidate that builds is provably the newest that does. Only
the skipping part assumes the boundary is monotone, and that assumption is genuinely
breakable: a window can read bad-good-bad-good from the tip backwards when one breakage was
fixed and another introduced, and a pure doubling search then lands on the older good
stretch. Measured on a synthetic window of exactly that shape — the tip broken, one day
back good, days 2–23 broken, day 24 and older good again — the default finds the true
newest in 3 builds while `--linear 0` settles 23 days further back and pays 10
(`tests/cases/flake-up-safe/12-linear-prefix-pays.sh` is that window). The prefix is
where a build still buys a day of freshness worth having; past it, the cap matters more
(nothing-works over a 60-candidate window costs ~15 builds instead of 60). A result that
comes out no newer than the baseline is discarded rather than pinned — the check is on
`lastModified` and not just on revision equality, because a channel list runs past the
baseline entirely when the baseline is not itself a published release.

Trials are keyed on the target's `.drv` path, so an input that does not reach the target
costs no build at all, and the composed result is built once more before it is written.
Composed locks are cached by recipe, verdicts by revision as well as by `.drv`. A build
that fails on a network error is retried once rather than being recorded as a broken
revision, and so is a `nix flake update` — a dropped packet while resolving an input says
nothing about the input and is not worth throwing a multi-hour run away for; one that fails
because the disk filled up aborts the run instead of blaming the inputs. Composition does
not `--refresh`, so it answers out of nix's `tarball-ttl` cache and a run longer than that
hour can see a tip move under it; anything that drifts is pinned back to the revision the
run recorded at the start, or two trials both saying "at its tip" would be testing two
different things. Reading the lock walks a `follows` path in `root.inputs` (`["a","b"]` =
root's input a, then that node's input b) rather than taking its last element, which names
the right node only by coincidence — and llm-agents deliberately carrying its own nixpkgs
node is exactly where the coincidence fails. The working tree's `flake.lock` is restored
on any failure or Ctrl-C. The run ends with `nix store diff-closures` against the
baseline, so the result is reported in packages
and not only in revisions. `-f DIR` picks the flake (default: the script's own repo, else
`$NH_FLAKE`, else the first `flake.nix` at or above `$PWD`), `-i NAME` restricts the search
to one input, `-v` streams nix's own output instead of a progress line. `-d N` is a count
of candidates, not a span of days — a candidate is a day for a commit search and a release
for a channel, and a rolling channel publishes several a day. `-t ATTR` names the build
outright and is refused alongside `-H`.

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

- `drtv-dl` — yt-dlp wrapper downloading DRTV series/seasons/films with Jellyfin naming (`Series/Season 01/Series - S01E01 - Title.ext`); carries a yt-dlp patch (`DRTVSeasonIE` entries `url` → `url_transparent` so series/season metadata reaches the output template, plus show descriptions/poster images surfaced on playlist results), and skips videos already on disk via a throwaway `--download-archive` (episodes found by a flat playlist scan; films and `-r` rechecks by a `--skip-download` probe that also refreshes their sidecars), so existing files are never rewritten by the metadata/subtitle embed. Generates Jellyfin sidecars as it goes: `tvshow.nfo` + poster/season posters per series, `.nfo` + thumb per episode, `.nfo` + poster per film — all with `<lockdata>true</lockdata>` so Jellyfin keeps DR's metadata instead of mismatching via TVDB/TMDB (the info.json→NFO conversion is jq in the script). The playlist scan classifies three ways, not two: video + `.nfo` present → download archive; video present, `.nfo` missing → handed to the `--skip-download` probe, so an ordinary run repairs sidecar gaps for the few episodes that have one instead of needing `-r` over everything (`scanned_bases` keeps the probe from counting those twice); nothing on disk → download. The thumbnail is deliberately not part of that test — DR has none for some videos, which would re-probe them forever. Progress is `[n/total] finished: path - N left, ~ETA`, the total being what both scans found missing before the run started. The progress announcer is a scratch `/bin/sh` script whose parameters arrive through the environment rather than being interpolated into its text — an apostrophe in the library path ("Emil's videos") otherwise closed the quoting and left a script that would not parse, so every progress line of an overnight run died silently. `-d` is normalised the same way standardebooks-dl's is, because the `-o` template renders `lib//X` where `find` reports `lib/X` and the `scanned_bases` lookup compares one against the other. `media_exists` excludes subtitle and text extensions as well as the NFO/image sidecars: an external `.srt` next to a video that is _not_ there would otherwise mark the episode downloaded for good. `-c` deletes yt-dlp's leftover scratch files (`.part`, `.part-Frag*`, `.ytdl`, per-format streams) from interrupted runs — every run reports what it finds, but only `-c` removes it, since a fragment may belong to a concurrent run. `-n` covers films too (one `--skip-download` probe each) and warns when a URL answers nothing, which is how DR taking a film down shows up. Reads URLs from a `drtv-series.txt` in the library root when given none.
- `standardebooks-dl` — pure-shell (curl + unzip) sync of a local Calibre-style library (`Last, First/Title/Title.{epub,azw3,kepub.epub,advanced.epub}` — one author directory, the epub's `file-as` sort name verbatim, same as Calibre's `{author_sort}`; an older `Last/First/Title` library is migrated in place on the next run, `-n` excepted — since the ledger otherwise keeps recreating legacy paths, the layout change alone would never reach books already synced) with the free ebooks at standardebooks.org. Enumerates the catalog from the site's `/sitemap` in one request, keeping only URLs ending in `/text` (the online reader) with the suffix stripped — the sitemap also lists ~2600 titles announced years ahead of their U.S. public-domain date, which have no files and used to cost a paced 404 probe every run; a published ebook has a `/text` subpage and a placeholder has none, and that filter was verified to reproduce all 31 pages of `/ebooks?per-page=48` exactly (1483 books). Author/title come from each epub's own `file-as` sort metadata, not the display name. A ledger (`DIR/.standardebooks-dl-index.tsv`) makes reruns incremental and resumable; it is a cache, not durable state — every SE epub carries its catalog URL as its OPF `dc:identifier` (translator segment included, so it _is_ the ledger's slug), so `rebuild_index` recovers the whole slug→path mapping from the epubs on disk, offline. That runs automatically when the ledger is missing/empty next to a non-empty library, and unconditionally under `-r`. Completeness is checked per format, not per folder (`media_count`/`media_exists` over all four extensions), and with `-s` rather than `-e` throughout, so a zero-byte file counts as missing instead of sticking forever. Lifts each book's embedded cover out as `cover.jpg` (path read from the epub's `cover-image` manifest item, so it's zero extra requests — Dolphin folder thumbnails + Calibre/Jellyfin artwork); `-r` backfills/repairs covers for an existing library straight from the local epubs (offline) and rebuilds the ledger in the same pass. Pacing is a quota ledger rather than a fixed delay (`quota_wait`/`quota_record` around every download, including the metadata probe): it mirrors the server's own algorithm — a timestamp per download the site actually served, in `${XDG_STATE_HOME:-~/.local/state}/standardebooks-dl/download-quota`, consulted before each request and slept against exactly (wait until the oldest ages out, never longer). It is keyed per machine, not per library, because the cap is per IP, and being on disk is the point: it survives restarts, where a fresh process would otherwise re-spend a budget already spent. Two runs sharing that ledger is a documented use (the cap is per IP, so two libraries synced from one machine draw on one budget), and pruning rewrites the whole file, so read-prune-write and append are both taken under an `flock` on `$quota_dir/lock` — without it a rewrite that began before another run's append landed dropped that append, and both runs then believed they had budget they had already spent. `util-linux` is a runtimeInput for that flock; run outside the Nix wrapper the script falls back to the old lock-free behaviour rather than refusing to start. `MIN_INTERVAL=30` only stops a whole window's budget going in a 90-second burst; the quota is the real constraint. A 429 now means the ledger disagrees with the server (lost ledger, browser downloads, shared NAT), so `fetch_url` waits it out with capped backoff for up to `LONG_WINDOW + 30m` instead of the old give-up-after-5-tries that marked good books failed — nothing can stay blocked longer than the 6h window, so outlasting it is the escape hatch. The old ≥8s/doubling-to-120s/never-recovering pacing was ~27x over the sustainable rate and assumed a penalty box that does not exist. A 5xx gets a small fixed budget of its own (60s, 120s, 180s, then give up): the site being down is not a verdict on a book, and without it a ten-minute maintenance window turns every remaining book in a fortnight-long run into a failure in the few minutes it takes to reach the end of the catalog. A download 404 is still tolerated (counted as "no files offered", not a failure) for a book caught mid-publication or renamed since the sitemap was generated, but with the `/text` filter it should no longer happen routinely. A run surveys the whole catalog against disk before fetching anything (stat-only, no requests) to build the `todo` set, so it can report `[n/total] outcome: Author/Title - N left, ~ETA` per book — the ETA is elapsed-per-book extrapolated, and `todo` is also exactly what `-n` prints, so the two can't drift. Both `-n` and a real run also report files-to-fetch (counted per format, not per book), the resulting estimate (`files × 6h/100`) and current quota spend up front; `-n` lists both what's missing entirely and what's on disk but short a format (`slug (n/4 formats)`), without downloading — and without writing: no ledger, no library directory, no migration, no covers. `-d` is normalised into a single strip prefix (`dest_prefix`) before anything uses it, because `-d lib/` otherwise yields a `lib//` prefix that matches nothing, puts absolute paths in the ledger, and makes the next run re-download the entire library. The author directory is the epub's `file-as` sort name with only Windows/SMB-illegal characters touched, which does trim a trailing period: "Milne, A. A." files under "Milne, A. A", the same trim Calibre makes.

  **SE's rate limit, measured 2026-07-30** (their site is open source — `standardebooks/web`, `www/ebooks/download.php` + `lib/Constants.php` — and live probing matched the source exactly). It applies **only to `/ebooks/*/downloads/*`**; `/sitemap`, catalog pages and book pages are unlimited (60 requests in 23s all returned 200, and kept returning 200 while downloads were blocked). Two sliding windows over _recorded_ downloads per IP: **more than 35 in 30s**, or **more than 100 in 6h** → 429 (`SHORT_DOWNLOAD_COUNT = 35`, `LONG_DOWNLOAD_COUNT = 100`, both compared with strict `>`). Verified: request 37 of an unpaced burst was the first 429, and with 74 already on the clock exactly 27 more succeeded before 429 at cumulative 101. There is **no penalty box** — a 429 is rejected before `AddDownload`, so it is never recorded and being blocked cannot extend the block; recovery is purely the window draining (measured 31.9s after a burst whose first request was at t=0.33s). The `RateLimitedIps` table an over-limit IP lands in only feeds `EbookDownload::IsBot()` for download _statistics_, it does not block. Logged-in (Patrons Circle) users skip the limiter entirely. Placeholders 404 _before_ the rate check, so probing them never cost quota — only wall-clock. **Sustained ceiling is therefore 100 files / 6h = 216s per file**, i.e. 14.4 min/book at 4 formats, so a full catalog sync is inherently ~2 weeks of wall time; the old 8s pace was ~27x over it, which is why a day-long run stalled. Probe the limiter with `curl -I` — HEAD runs `download.php` so it counts and 429s identically, but moves no file body.

  **Hazard:** a hidden `/honeypot` link in the site header is wired to fail2ban with `bantime = 24h, maxretry = 1` — a single GET firewall-bans the IP for 24 hours. Never follow SE links blindly; only construct download/catalog URLs.

- `vuescan` — unfree scanner binary fetched from a personal mirror (github.com/emillassen/binary-mirror releases), autoPatchelf'd; the release tag/URL interpolates `version`.
- `devilutionx` — built from a pinned upstream master commit with vendored dependency pins (`FETCHCONTENT_SOURCE_DIR_*`); refresh with `pkgs/devilutionx/update.sh`.

## Tests

`tests/` holds a hermetic bash suite for the three big shell scripts
(`flake-up-safe.sh`, `standardebooks-dl.sh`, `drtv-dl.sh`). It is **deliberately not part
of `nix flake check`**: it needs no Nix daemon and no network, and keeping it out means
`nix flake check` stays what it was. Run it with `./tests/run.sh`; it exits non-zero if any
case fails, and a full run is about half a minute.

- `tests/run.sh` — the runner. Arguments are substring filters on the case path.
- `tests/lib/` — `assert.sh` (assertions that report case, expectation and actual, and keep
  going), `harness.sh` (temp dirs, PATH assembly, preamble synthesis, `extract_funcs`),
  `sim-flake.sh` / `se.sh` / `drtv.sh` (per-target scenario builders), `mkepub.py`.
- `tests/stubs/` — programmable fakes for `nix`, `git`, `curl`, `gh`, `yt-dlp`, `date` and
  `sleep`. Each reads a scenario file and logs its own invocations, which is what makes
  "how many builds did that cost" and "was this episode extracted at all" assertable.
- `tests/cases/<script>/NN-name.sh` — one case per file.

Every case works in a fresh temp directory and points `TMPDIR` inside it, so the scratch
directories the scripts make for themselves go too — `flake-up-safe.sh` deliberately
_keeps_ its working directory whenever a run fails or holds an input back, which most of
its cases do on purpose, and a full run would otherwise leave a few hundred of them in
`/tmp`.

Two things about the design are load-bearing. **The two `pkgs/` fragments have no shebang
and no `set` line**: `writeShellApplication` supplies `set -o errexit/nounset/pipefail`, so
running one with plain `bash file.sh` drops all three and hides exactly the class of bug
worth hunting. The harness synthesizes that preamble itself
(`tests/cases/harness/00-preamble.sh` guards the assumption). And **runtimeInputs are
_prepended_ to PATH**, so a stub can never shadow the real `yt-dlp` or `curl` inside a
built derivation — which is why the suite runs the raw fragment under its own preamble with
PATH pointing at the stub directory, and leaves the real-derivation check to
`tests/build-check.sh`.

Nothing in the suite touches the network. For standardebooks.org that is not merely tidy: a
hidden `/honeypot` link in their page header is wired to fail2ban with `maxretry = 1,
bantime = 24h`.

Extending the suite is what the `/test-scripts` skill
(`.claude/skills/test-scripts/`) is for: its `references/` carry the stub contracts, the
findings ledger (fixed, refuted, still uncovered) and the bash traps that have already
cost a debugging round.

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
- Pre-commit hooks (defined in flake.nix, run by `nix flake check` and on commit): nixfmt, statix, deadnix, shellcheck (`scripts/*.sh` only — the scripts under `pkgs/` are shebang-less `writeShellApplication` fragments, which shellchecks them at build time instead), prettier (yaml/markdown, excluding `secrets/`), sops-encrypted, plus standard hygiene hooks. The root `.pre-commit-config.yaml` is a gitignored symlink generated by the dev shell.
- Git: **work directly on `main` — do not create a branch to commit.** This is a single-user config repo with no human PR workflow and CI disabled, so a branch just leaves work stranded behind a merge the owner has to do by hand. Commit to `main` when asked to commit; `nix flake check` is the gate that would otherwise be a review. (The `update-*` and `claude/*` branches on the remote are bot-opened PR branches — leave them alone.)
- Git: commits are GPG-signed by default (key on a YubiKey — a touch may be required). SSH remote operations also need the YubiKey; the `gh` CLI is authenticated and is the reliable path for GitHub API/HTTPS operations. Commit style: short imperative subject line, then a body explaining the why (see `git log`).
- `pkgs.stable` = nixpkgs 26.05; the primary channel is nixos-unstable.
