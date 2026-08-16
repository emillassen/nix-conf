# Findings ledger

State of the three scripts as of the last pass. Read it before hunting, so a
fixed bug is not re-reported as a discovery and a refuted hypothesis is not
re-chased.

- [Fixed, with a case that catches the regression](#fixed-with-a-case-that-catches-the-regression)
- [Refuted](#refuted)
- [Corrected documentation](#corrected-documentation)
- [Known gaps in coverage](#known-gaps-in-coverage)
- [Decided, deliberately left alone](#decided-deliberately-left-alone)

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

| Finding                                                                                                                                                                                                                                                                                                              | Case                               |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| **High.** Trailing-slash `-d` left absolute paths in the ledger, so the next run re-downloaded the whole library — days of wall time against a 100-per-6h cap. Now one `dest_prefix`.                                                                                                                                | `02-dest-forms`                    |
| `&amp;` was never unescaped (bash 5.2's `&` in a replacement), so every title with an ampersand got a directory named `Dr. Jekyll &amp; Mr. Hyde`.                                                                                                                                                                   | `08-epub-reading`, `01-first-sync` |
| The quota ledger lost records with no lock, so two runs overran the site's limit. Now `flock`; `util-linux` added to runtimeInputs.                                                                                                                                                                                  | `06-quota-concurrency`             |
| A 5xx failed a book outright, so a maintenance window turned the rest of the catalog into failures.                                                                                                                                                                                                                  | `05-fetch-backoff`                 |
| `-n` created the library directory and an empty ledger.                                                                                                                                                                                                                                                              | `10-dry-run-and-catalog`           |
| **Medium.** A bare `mkdir -p` in the download loop ended the whole run at the first author directory that would not take a write: exit 1, no summary, no warning list, every book after it abandoned however far into a fortnight the run was. Guarded like every other per-book step now, as is the `mv` beside it. | `11-partial-failures`              |

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
- **`s3_releases`' pagination is correct**, including the marker it carries over
  (the last `CommonPrefix` of the page, which is what S3's own `NextMarker`
  would be) and the request prefix S3 echoes back as a bare `<Prefix>` ahead of
  them, which is filtered out by the release-name regex rather than mistaken for
  a release (`27-s3-pagination`).
- **The build-level retry cannot loop.** `attempt -eq 1` bounds it at two, and
  the second attempt is not re-tested for transience (`24-fatal-and-build-retry`).
- **`-v`'s `tee` pipeline does not swallow a failed build.** `set -o pipefail` is
  in force, so the pipeline reports the build's status and not tee's
  (`26-tty-and-verbose`).
- **The flake-discovery chain resolves in the documented order**, and an
  installed copy with no flake above it falls through to `$NH_FLAKE` rather than
  to `$PWD` (`23-flake-discovery`). `NH_FLAKE=` set but empty falls to a `$PWD`
  walk, which is the next fallback anyway, so the `${NH_FLAKE-…}` vs `:-` spelling
  cannot mis-decide.

## Corrected documentation

CLAUDE.md's measured claim for the bad-good-bad-good window was half right. On a
window of that shape — tip broken, one day back good, days 2–23 broken, day 24
and older good — the default does find the true newest in 3 builds, and
`--linear 0` does settle 23 days further back, but it pays 10 builds, not the 7
previously written down. `12-linear-prefix-pays` is that window.

## Known gaps in coverage

Not known bugs. Places a bug could sit unobserved, which is where a new pass
should start. Everything the last pass closed has been struck; what is left is
genuinely uncovered.

- **`s3_releases`' "no `CommonPrefixes` but truncated" page.** The pagination
  loop takes its next marker from the last `<Prefix>`, which on such a page is
  the echoed request prefix — the same value it already used, so the loop would
  not advance. `IsTruncated` guards it and the shape looks unreachable against
  the real bucket (everything under `nixos/unstable/` collapses into a common
  prefix), but nothing proves it.
- **`REV_VERDICT` and `REV_TS` are never reset between inputs** in the bisect
  loop, while `CAND_REV_MEMO` and the `LOOKUPS_*` counters are. A verdict is
  keyed on a revision alone, but it was reached under the `KEPT`/`PINS` state in
  force at the time, and `PINS` grows as each input is settled. Two inputs would
  have to share a repository for it to bite — nixpkgs and nixpkgs-stable do —
  and their branches would have to share a revision inside the search window,
  which is why this is a gap and not a finding.
- **An unresolvable candidate counts as a failure** in the walk: it sets `lo`
  and consumes a slot of the `--linear` prefix, so a GitHub hiccup over the
  newest few days quietly weakens the prefix's "everything newer was tried and
  failed" guarantee. `13-github-unreachable` covers the all-failed case, not a
  partial one.
- **`fetch_one`'s `mv` and `quota_record`** are still bare commands under
  `set -e`, unlike the two `mkdir -p` calls beside them. Both are far less
  reachable (the directory has just been proven writable, and the state dir is
  created at startup), but they are the same class as the fixed defect.
- **Subtitle and metadata embedding** (`--embed-subs`, ffmpeg) and yt-dlp's
  `--parse-metadata` engine are out of scope by design. Say so again rather than
  faking them badly.

## Decided, deliberately left alone

- **drtv-dl's library-wide info.json sweep.** `find "$dest" -name '*.info.json'`
  is run twice per run and deletes every file it finds, so two drtv-dl runs into
  one library will eat each other's sidecar material: run B's NFO pass sees run
  A's info.json for an episode still downloading, finds no video beside it, and
  deletes the json and the thumb as litter. Run A then finishes with no sidecars
  and says nothing.

  Left as it is, on purpose, and this is the decision rather than a deferral.
  The sweep being library-wide is what repairs an interrupted run — its
  info.jsons are converted on the next ordinary run — and scoping it to the
  current run would trade a real recovery path for a hazard the help text
  already warns about under `-c` ("Don't use it while another drtv-dl is
  downloading into the same library"). A correct narrowing needs per-run
  provenance for sidecars, which nothing currently records; an mtime cutoff is
  the cheap approximation and is wrong across any run long enough to matter.
  Reopen only with a design for that provenance, not with a new report of the
  symptom.
