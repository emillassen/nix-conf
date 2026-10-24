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
| `REV_VERDICT`/`REV_TS` lived for the whole run, so a second input meeting a revision the first had tried took its verdict without a trial. Now reset per input.                                                               | `28-verdicts-per-input`         |
| Daily candidates were cut off by timestamp, so the baseline's own day was dropped whenever the tip's time of day was earlier. Now compared as calendar days.                                                                  | `29-candidate-days`             |
| An unresolved candidate counted as a failed build, so the result claimed "newest" with a newer one never named. Now walked past, remembered and reported.                                                                     | `29-candidate-days`             |
| A failed S3 listing read as "tip not a published release" and fell back to a commit search. Now the input is left unresolved.                                                                                                 | `30-s3-listing-fails`           |
| Host discovery's `nix eval` ran before the lock backup (and could write the lock); no flock against a second run; a failed lock-cache `cp` passed as a composed lock; `-k` failures skipped `abort_if_fatal`; no eval retry.  | `31-environment-failures`       |
| SIGTERM/SIGHUP exited with the background nix still running, and off a terminal the trap waited for the foreground build. nix now runs in the background, is killed by the trap, and never inherits the flock fd.             | `32-signal-stops-child`         |
| `printf \| grep -q` on the S3 page SIGPIPEd once `IsTruncated` came first. Latent: the real bucket answers on one line, so grep reads it whole. Now a substring test.                                                         | `27-s3-pagination`              |

### `pkgs/standardebooks-dl/standardebooks-dl.sh`

| Finding                                                                                                                                                                                                                                                                                                              | Case                               |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| **High.** Trailing-slash `-d` left absolute paths in the ledger, so the next run re-downloaded the whole library — days of wall time against a 100-per-6h cap. Now one `dest_prefix`.                                                                                                                                | `02-dest-forms`                    |
| `&amp;` was never unescaped (bash 5.2's `&` in a replacement), so every title with an ampersand got a directory named `Dr. Jekyll &amp; Mr. Hyde`.                                                                                                                                                                   | `08-epub-reading`, `01-first-sync` |
| The quota ledger lost records with no lock, so two runs overran the site's limit. Now `flock`; `util-linux` added to runtimeInputs.                                                                                                                                                                                  | `06-quota-concurrency`             |
| A 5xx failed a book outright, so a maintenance window turned the rest of the catalog into failures.                                                                                                                                                                                                                  | `05-fetch-backoff`                 |
| `-n` created the library directory and an empty ledger.                                                                                                                                                                                                                                                              | `10-dry-run-and-catalog`           |
| **Medium.** A bare `mkdir -p` in the download loop ended the whole run at the first author directory that would not take a write: exit 1, no summary, no warning list, every book after it abandoned however far into a fortnight the run was. Guarded like every other per-book step now, as is the `mv` beside it. | `11-partial-failures`              |
| `migrate_index` rewrote every legacy ledger path whether or not its directory had moved, so a collided or failed move had its complete book fetched again. Now: rewrite unless the legacy directory still exists. The migration's own `mkdir -p` was bare too.                                                       | `12-migration-ledger`              |
| `fetch_one`'s final `mv` ran unchecked under the caller's `\|\| ok=0`, so a failed rename was "downloaded". The ledger append after a probe was bare under set -e.                                                                                                                                                   | `12-migration-ledger`              |
| **High.** Two slugs with the same sanitized author/title shared a directory and mixed their formats. Now a directory the ledger or an epub on disk gives to another entry is never taken; a later comer is `Title (slug-tail)`.                                                                                      | `13-shared-directory`              |
| `-n` created, locked and pruned the quota ledger, and beside a lost ledger reported a complete library as missing. Now a read-only count, and the mapping is recovered into scratch.                                                                                                                                 | `10-dry-run-and-catalog`           |
| A 200 followed by a curl error (18/23/28) was not recorded in the quota, though the site counted it. Now `fetch_url` returns 3 for it and both callers record it.                                                                                                                                                    | `05-fetch-backoff`, `11-…`         |

### `pkgs/drtv-dl/drtv-dl.sh`

| Finding                                                                                                                                                                                                                                                               | Case                                   |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| **High.** The generated `announce` script broke on an apostrophe in the library path, so every progress line of an overnight run died and the summary reported nothing downloaded. Now a quoted heredoc reading the environment.                                      | `02-library-paths`                     |
| `${url//Format='png'/…}` never matched (quote removal in the pattern half), so replaced posters were PNGs under a `.jpg` name.                                                                                                                                        | `06-posters`                           |
| Trailing-slash `-d` made the `scanned_bases` lookup miss and double-counted the summary.                                                                                                                                                                              | `04-sidecar-repair`                    |
| `media_exists` counted a stray `.srt` as the video.                                                                                                                                                                                                                   | `03-media-exists`                      |
| Another tool's `.info.json` was converted to an NFO, deleted, or counted; now only `extractor_key` DRTV\* jsons are touched. A symlinked `-d` was never descended (`find -H` now). Empty NFOs passed for sidecars; jq failures emptied good ones (temp + rename now). | `13-library-safety`                    |
| An empty video counted as present for good (yt-dlp skips any file at the final name); now `-f`/`-s`, and an empty one is removed so it is fetched again.                                                                                                              | `13-library-safety`, `03-media-exists` |
| `-c` deleted a finished `X.f1.mp4` (spared now when `X.f1.nfo` is beside it) and called an unreadable library clean; `-n` exited 0 with a playlist it could not scan.                                                                                                 | `13-library-safety`                    |

## Refuted

Each has a case pinning the correct behaviour. Do not re-open without new
evidence.

- **The tip-drift stub does drift** (`17-tip-drift`). A review read
  `grep -q "^$n\t"` in `tests/stubs/nix` as a backslash-t; the file has a real
  TAB there (`cat -A` shows `^I`).
- **The S3 pagination SIGPIPE is not live against the real bucket.** It answers
  on one line, and grep has to read a whole line before it can match. Fixed
  anyway, since it was one substring test away; the stub now emits the shape
  that would trip it.

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

AGENTS.md's measured claim for the bad-good-bad-good window was half right. On a
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
- **`quota_record` is still a bare command.** In the probe path it is the last
  command of an `&&` list in the main loop, so a quota ledger that stops taking
  writes ends the run there. Reachable only if the state directory goes away
  mid-run; same class as the fixed `mkdir -p`/append defects.
- **Quota admission is not atomic across two runs.** Each reads the ledger and
  records after its request, so both can take a window's last slot; the 429
  wait absorbs it. Documented, not fixed.
- **The harness runs cases without errexit**, so an unexpected failure in a
  case's own setup is invisible unless an assertion notices. Making it fatal
  needs an audit of every case for commands that fail on purpose.
- **The nix and git stubs accept any flags**: `path-info` without
  `--derivation`, `build` without `--print-out-paths`, `git` without `-C` all
  still answer, so losing one of those in production would not show.
- **`06-quota-concurrency` is scheduling-dependent**: the fake `sleep` returns at
  once, so the "child blocked on the lock" phase does not prove the child ever
  tried. It still catches a removed lock under the stress phase in practice.
- **The verbose (`-v`) route still runs nix in the foreground**, inside a
  `tee` pipeline, so a SIGTERM there waits for the build like the old pipe
  route did. Killing a pipeline member from the trap needs its pid, which a
  plain pipeline does not give.
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
  (Narrowing it to jsons whose `extractor_key` is DR's is not a narrowing of
  this kind: an interrupted DR run's jsons are still DR's, so the recovery path
  is whole. That only stops other tools' info.jsons being converted or deleted.)
  The sweep being library-wide is what repairs an interrupted run — its
  info.jsons are converted on the next ordinary run — and scoping it to the
  current run would trade a real recovery path for a hazard the help text
  already warns about under `-c` ("Don't use it while another drtv-dl is
  downloading into the same library"). A correct narrowing needs per-run
  provenance for sidecars, which nothing currently records; an mtime cutoff is
  the cheap approximation and is wrong across any run long enough to matter.
  Reopen only with a design for that provenance, not with a new report of the
  symptom.
