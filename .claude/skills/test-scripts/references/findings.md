# Findings ledger

State of the three scripts as of the last pass. Read it before hunting, so a
fixed bug is not re-reported as a discovery and a refuted hypothesis is not
re-chased.

- [Fixed, with a case that catches the regression](#fixed-with-a-case-that-catches-the-regression)
- [Refuted](#refuted)
- [Corrected documentation](#corrected-documentation)
- [Known gaps in coverage](#known-gaps-in-coverage)
- [Open questions](#open-questions)

## Fixed, with a case that catches the regression

Verify these are still fixed by reverting each and running the named case; do
not re-report them as new.

### `scripts/flake-up-safe.sh`

| Finding                                                                                                                                                                                                                       | Case                            |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- |
| `--linear N` gave a prefix of N+1 and `--linear 0` still checked two, so "skip from the start" was unexpressible. Now counted in probes made.                                                                                 | `11-linear-walk-table`          |
| A `follows` path in `root.inputs` (`["a","b"]`) resolved with `.value[-1]`, which names the right node only by coincidence — and llm-agents carrying its own nixpkgs node is where the coincidence fails. Now walks the path. | `15-follows-path`               |
| `compose()` does not `--refresh`, so past `tarball-ttl` a later trial composed a newer tip than the run recorded; the recipe cache does not prevent it, since each half is its own recipe. Drift is now pinned back.          | `17-tip-drift`                  |
| Unresolvable candidates were reported as "No revision newer than the baseline builds" — a build verdict about revisions never built.                                                                                          | `13-github-unreachable`         |
| The S3 `marker`, guessed from the tip's year, skipped a stable channel's entire listing once the channel was over a year old, silently dropping to a commit search.                                                           | `19-s3-marker`                  |
| A transient `nix flake update` failure killed the run while builds got a retry.                                                                                                                                               | `18-transient-update`           |
| `-t` silently ignored `-H`.                                                                                                                                                                                                   | `16-target-and-host`            |
| `--max-days` documented as a candidate count, not a span of days.                                                                                                                                                             | `14-max-days-counts-candidates` |

### `pkgs/standardebooks-dl/standardebooks-dl.sh`

| Finding                                                                                                                                                                               | Case                               |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| **High.** Trailing-slash `-d` left absolute paths in the ledger, so the next run re-downloaded the whole library — days of wall time against a 100-per-6h cap. Now one `dest_prefix`. | `02-dest-forms`                    |
| `&amp;` was never unescaped (bash 5.2's `&` in a replacement), so every title with an ampersand got a directory named `Dr. Jekyll &amp; Mr. Hyde`.                                    | `08-epub-reading`, `01-first-sync` |
| The quota ledger lost records with no lock, so two runs overran the site's limit. Now `flock`; `util-linux` added to runtimeInputs.                                                   | `06-quota-concurrency`             |
| A 5xx failed a book outright, so a maintenance window turned the rest of the catalog into failures.                                                                                   | `05-fetch-backoff`                 |
| `-n` created the library directory and an empty ledger.                                                                                                                               | `10-dry-run-and-catalog`           |

### `pkgs/drtv-dl/drtv-dl.sh`

| Finding                                                                                                                                                                                                                          | Case                |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- |
| **High.** The generated `announce` script broke on an apostrophe in the library path, so every progress line of an overnight run died and the summary reported nothing downloaded. Now a quoted heredoc reading the environment. | `02-library-paths`  |
| `${url//Format='png'/…}` never matched (quote removal in the pattern half), so replaced posters were PNGs under a `.jpg` name.                                                                                                   | `06-posters`        |
| Trailing-slash `-d` made the `scanned_bases` lookup miss and double-counted the summary.                                                                                                                                         | `04-sidecar-repair` |
| `media_exists` counted a stray `.srt` as the video.                                                                                                                                                                              | `03-media-exists`   |

## Refuted

Each has a case pinning the correct behaviour. Do not re-open without new
evidence.

- **`REV_TS`'s `:-0` fallback cannot mis-decide.** Revision equality is tested
  first and short-circuits, and the only revision without a `REV_TS` entry is the
  pre-seeded baseline (`22-candidate-is-baseline`).
- **Empty-array expansion under `set -u` is safe** on bash 5.3, so the one
  `${ONLY[@]+…}` guard was dropped rather than three added.
- **`media_exists` handles glob metacharacters correctly** — `"$1".*` quotes the
  variable, so `[`, `*` and `?` in a title match literally.
- **The `.part`/`.ytdl` comment is right.** yt-dlp names leftovers after the
  _final_ filename, so they carry two extension tokens. A fixture named
  `Ep.part` tests nothing real.
- **flake-up-safe's "final combination does not hold" fallback is unreachable via
  a build failure.** The final composition is byte-identical to a state already
  verified, so the `.drv` cache always answers it; only an evaluation failure
  gets there, which is what `09-final-verification-fails` uses.

## Corrected documentation

CLAUDE.md's measured claim for the bad-good-bad-good window was half right. On a
window of that shape — tip broken, one day back good, days 2–23 broken, day 24
and older good — the default does find the true newest in 3 builds, and
`--linear 0` does settle 23 days further back, but it pays 10 builds, not the 7
previously written down. `12-linear-prefix-pays` is that window.

## Known gaps in coverage

Not known bugs. Places a bug could sit unobserved, which is where a new pass
should start.

- **`run_nix`'s terminal branch.** Cases always redirect stdout to a file, so
  `TTY=0` and the background-pid/progress-line path — and `-v`'s tee pipeline —
  has never run. Both do real work with `wait` and exit codes.
- **`abort_if_fatal`** (disk full, daemon gone) and the build-level
  `is_transient` retry. The update-level retry is covered; the build one is not.
- **`check_lock`'s `LOCK_CHECKED` cache.** `-k` is exercised for pass/fail, not
  for reuse across two trials with the same lock.
- **`find_flake_root`** and the `$NH_FLAKE` / `$PWD` discovery chain; every case
  passes `-f`.
- **`check_single_season`** in drtv-dl (the "this is one season of N" warning),
  which needs a `production-cdn.dr-massive.com` entry in the curl map.
- **`fetch_one`'s "200 with an empty body"** branch, and `migrate_layout`'s `mv`
  failure branch.
- **Subtitle and metadata embedding** (`--embed-subs`, ffmpeg) and yt-dlp's
  `--parse-metadata` engine are out of scope by design. Say so again rather than
  faking them badly.

## Open questions

- **drtv-dl's library-wide info.json sweep.** `find "$dest" -name '*.info.json'`
  deletes every one it finds, so two concurrent runs into one library would eat
  each other's sidecar material — the script already warns against concurrent
  `-c` for the same reason. Left alone last pass as larger than the pass
  warranted. Decide, rather than rediscovering it.
