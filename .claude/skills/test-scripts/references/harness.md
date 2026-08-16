# The harness: layout, helper API, stub contracts

Read this before writing a case or touching a stub. Everything here is
established and working; the point of the document is that none of it is
guessable from the file listing.

- [Layout](#layout)
- [Case skeleton](#case-skeleton)
- [Harness API](#harness-api)
- [Assertions](#assertions)
- [Scenario builders](#scenario-builders)
- [Stub contracts](#stub-contracts)
- [Adding a stub](#adding-a-stub)
- [Why not bats or shellspec](#why-not-bats-or-shellspec)

## Layout

```
tests/run.sh              runner; arguments are substring filters on the case path
tests/build-check.sh      builds both pkgs/ derivations for real; run by hand
tests/.shellcheckrc       SC1091/SC2016/SC2034 disabled, each with a reason
tests/lib/assert.sh       assertions
tests/lib/harness.sh      lifecycle, PATH assembly, preamble synthesis, extract_funcs
tests/lib/sim-flake.sh    the flake universe for flake-up-safe cases
tests/lib/se.sh           a fake standardebooks.org
tests/lib/drtv.sh         drtv scenario builder
tests/lib/mkepub.py       real SE-shaped epub zips, one flag per edge case
tests/stubs/              nix git curl gh yt-dlp date sleep
tests/cases/<script>/NN-name.sh
tests/cases/harness/      cases that test the suite's own assumptions
```

## Case skeleton

```bash
#!/usr/bin/env bash
# One paragraph on what this case is about and why it is worth a case.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"          # or sim-flake.sh / drtv.sh, or nothing
test_init "standardebooks-dl: what this checks"

se_init
se_book milne/now-we-are-six "Milne, A. A." "Now We Are Six"
se_sitemap

run_sedl -d "$SE_LIB"

assert_exit "exits 0" 0
assert_file_exists "the book lands" "$SE_LIB/Milne, A. A/Now We Are Six/Now We Are Six.epub"
```

`test_init` installs the EXIT trap that reports and sets the status; there is no
"end" call. A case that dies early is reported as a failure, not a pass.

## Harness API

| Call                                          | Does                                                                      |
| --------------------------------------------- | ------------------------------------------------------------------------- |
| `test_init "label"`                           | temp dir, stub dir, stub log, `REALBIN`, `TMPDIR`, proxy guard, EXIT trap |
| `use_stubs nix git curl …`                    | copy named stubs into the case's stub dir                                 |
| `stub_noop NAME [rc]`                         | a stub that only records its argv                                         |
| `stub_log NAME` / `stub_count NAME [pattern]` | read the invocation log                                                   |
| `require_tool unzip python3 flock`            | real tools, falling back to `/nix/store/*-<tool>-*/bin/<tool>`            |
| `use_test_path`                               | put the stub dir on `PATH` for functions run in the case's own shell      |
| `run_fragment SCRIPT args…`                   | synthesize the writeShellApplication preamble and run                     |
| `run_flake_up_safe args…`                     | run the real script (it has its own shebang and `set`)                    |
| `run_sedl` / `run_drtv`                       | thin wrappers over `run_fragment`                                         |
| `RUN_CWD=DIR run_… `                          | run from somewhere else; `-d .` only means something relative to a cwd    |
| `extract_funcs FILE OUT name…`                | pull named functions out of a script to source directly                   |
| `wrap_fragment SCRIPT OUT`                    | the preamble synthesis on its own                                         |

Results land in the globals `STATUS`, `STDOUT`, `STDERR` — **not** on stdout, so
`x="$(run_drtv …)"` throws them away in a subshell. Have a helper set a
variable.

`extract_funcs` is deliberately strict: a function that has been renamed or
reformatted makes the case error out loudly rather than quietly testing nothing.
It requires `name() {` at column 0 and `}` at column 0.

`test_init` also points `TMPDIR` inside the case directory. Keep that property
for any new execution route: flake-up-safe.sh keeps its `WORKDIR` on purpose on
any failure or held-back input, which most of its cases produce, and a full run
would otherwise leave hundreds of directories in `/tmp`.

## Assertions

`assert_eq`, `assert_ne`, `assert_contains`, `assert_not_contains`,
`assert_matches`, `assert_exit`, `assert_file_exists`, `assert_file_missing`,
`assert_file_contains`, `assert_files_identical`, and `fail`.

All take a label first, all report expected-vs-actual, and none of them stops
the case — eight failures should be visible in one run, not one per invocation.
`assert_files_identical` is byte-for-byte, which is what "the working tree was
left exactly as found" actually means.

## Scenario builders

**`sim-flake.sh`** — `sim_init`, `sim_input NAME OWNER/REPO REF BASEREV BASETS
TIPREV TIPTS`, `sim_write`, `sim_verdict` (heredoc; stdin is the combination,
exit 0 = builds), `sim_check`, `sim_reaching`, `sim_rev`, `sim_gh_day`,
`sim_gh_dead`, `sim_channel_releases PREFIX VERSION SEP` (stdin:
`serial<TAB>fullrev<TAB>ts`), `sim_channel_filler PREFIX COUNT [VERSION]` (keys
only, no revisions — pads a listing past the bucket's 1000-key page so the tip
lands on page two). Read results with `lock_rev`, `lock_ts`, `builds_run`,
`build_combos`, `probed_indices`.

Unlike the other two builders, `sim_init` does **not** clear the stub logs; cases
that call it twice do `rm -f "$STUBLOG/builds.log"` themselves, and several
already rely on that.

`idxrev N` makes a 40-hex revision whose first seven characters are the
candidate index, so the ten characters flake-up-safe prints per probe _are_ the
index — that is what makes a walk's visiting order assertable without
reverse-engineering dates. `probed_indices "$STDOUT"` reads them back.

**`se.sh`** — `se_init [epoch]`, `se_book SLUG FILEAS TITLE [mkepub flags…]`,
`se_placeholder SLUG`, `se_sitemap`, `se_touch_book DIR BASE`, `run_sedl`,
`now`/`set_now`, `quota_ledger`.

**`drtv.sh`** — `drtv_init`, `drtv_meta URL JSON`, `drtv_video URL JSON`,
`drtv_child PARENT CHILD`, `drtv_playlist URL`, `run_drtv`, `drtv_events`,
`drtv_extractions`.

`se_init` and `drtv_init` both **start over completely**: empty library, empty
stub logs, and for `se_init` an unspent quota ledger. That matters for a case
with two scenarios in it — a count taken after the second one would otherwise
include the first one's calls, a book left on disk would be judged complete, and
the curl stub's per-URL consume counters would still be part-way through the
previous scenario's list. All three read as plausible results rather than as
mistakes, which is why the reset is in the builder and not in the case.

**`mkepub.py`** builds real zips, because the script reads them with the real
`unzip`; a fixture that only pretends to be an epub tests the fixture. One flag
per edge: `--opf-path`, `--cover-href`, `--cover-href-xml`, `--cover-bytes`,
`--properties`, `--no-cover-item`, `--no-identifier`, `--corrupt`.

## Stub contracts

Every stub logs its argv to `$STUBLOG/<name>.log`. That is what makes "how many
builds did that cost" and "was this episode extracted at all" assertable, and it
is the only way the efficiency claims in CLAUDE.md can be checked.

**`nix`** — universe in `$FLAKE_SIM`:

| File                               | Meaning                                                         |
| ---------------------------------- | --------------------------------------------------------------- |
| `tips`                             | `name<TAB>rev<TAB>lastModified`; where `nix flake update` lands |
| `tips-drift`                       | where a _non_-`--refresh` update lands instead (a moved tip)    |
| `revs`                             | `rev<TAB>lastModified` for every revision the sim knows         |
| `reaching`                         | which inputs affect the target `.drv` (absent = all)            |
| `verdict.sh`                       | stdin is the combination; exit 0 = this lock builds             |
| `eval.sh`                          | same shape, for `nix path-info`                                 |
| `check.sh`                         | same shape, for `nix flake check`                               |
| `pin-noop` / `pin-fail`            | `--override-input` stops writing / fails                        |
| `update-fail` / `update-fail-once` | a wall / a transient blip                                       |
| `diff`                             | output for `nix store diff-closures`                            |

The synthetic `.drv` is a hash of the _reaching_ inputs only, so `.drv`-equality
caching is genuinely exercised — including the case where an input's update does
not reach the target and the trial must cost no build.

`verdict.sh`, `eval.sh` and `check.sh` are all handed the combination through a
**file**, never a pipe: a body that exits without reading stdin would otherwise
SIGPIPE the writer and invert its own verdict. See `bash-traps.md`.

A case that needs the terminal route through `run_nix` supplies its own pty —
`require_tool script` and `script -qec "$cmd" /dev/null`, as
`26-tty-and-verbose` does. `script` merges stderr into the pty, so for those runs
everything arrives in `STDOUT` and `STDERR` is empty.

**`curl`** — TSV at `$CURL_MAP`: `URLGLOB<TAB>STATUS<TAB>PAYLOAD`.

- `@/abs/path` is served byte-for-byte, so real zips survive.
- `-` is an empty body; `000` is a connection failure (exit 7).
- `!s3 /abs/keyfile` answers as the nix-releases bucket does, **honouring the
  `marker` and `max-keys` parameters** and echoing the request's own `prefix`
  back as a bare `<Prefix>` ahead of the `CommonPrefixes`, exactly as S3 does. A
  caller's guess at a marker is therefore part of the test, so is its handling of
  `<IsTruncated>true</IsTruncated>`, and so is its not mistaking the echo for a
  release. Pair it with `sim_channel_filler` to push a tip onto page two.
- Several lines may match one glob: they are consumed in order and the last one
  sticks, which is how "429, 429, then 200" is written.

**`gh`** — TSV at `$GH_MAP`: `PATHGLOB<TAB>PAYLOAD`; `-` means the request fails,
which is an unreachable or rate-limited GitHub.

**`date` / `sleep`** — `$FAKE_CLOCK` holds epoch seconds. `date +%s` reads it and
everything else delegates to the real `date`; `sleep` records its argument and
advances the clock. Hours of quota waiting run in milliseconds and the exact
schedule is assertable.

**`yt-dlp`** — JSON at `$YTDLP_SCENARIO` with `playlists`, `playlist_meta` and
`videos`. Reproduced faithfully: the output-template constructs drtv-dl uses
(`%%`, `%(a,b)s`, `%(field&TEXT|FALLBACK)s` with `{}` and `{:02d}`, and the `⧸`
substitution yt-dlp makes for a slash inside a replacement), the four `--output`
keys, flat versus full extraction, `--download-archive` matched pre-extraction
against the playlist's id and the URL slug, `--write-info-json`,
`--write-thumbnail` and `--exec after_move:`. A video may carry `flat_id`
distinct from `id`, to model the case the two-line archive exists for.

Not reproduced: `--parse-metadata`. Those four regexes are yt-dlp's engine, not
drtv-dl's logic, so the stub applies their _effect_ directly and scenarios supply
titles as DR gives them. Say so rather than faking it badly.

## Adding a stub

1. Write it in `tests/stubs/<tool>`, first line `#!/usr/bin/env bash`, second
   `set -uo pipefail` — never `-e`, a stub that exits on a failed match is
   unreadable.
2. Log argv to `$STUBLOG/<tool>.log` before anything else.
3. Read the scenario from a file named by an environment variable the case sets,
   never from hardcoded data. Hardcoded fakes rot the moment there is a second
   case.
4. Make an unmatched request a loud failure, not a plausible default. A case
   that reaches a URL nobody declared should notice.
5. Add it to the "Stub contracts" table above in the same change.

## Why not bats or shellspec

Both exist, both are good, and PATH-shadowed stub scripts — the technique the
harness uses — is exactly what their mocking add-ons (`bats-mock`, shellmock)
provide. They are still the wrong choice here:

- They would have to be added to `flake.nix` to be available in `nix develop`,
  and touching `flake.nix` is forbidden by this skill's first constraint.
- They would replace `run.sh` plus `assert.sh` — about 250 lines. The other
  ~1,500 lines are the preamble synthesis and the scenario-driven stubs, which
  no framework provides and which are the actual work.
- The suite has no dependency beyond bash, coreutils, jq and python3, so it runs
  from a bare checkout with nothing installed. That is worth more here than
  TAP output.

Do not spend a pass migrating it. Record the decision instead if it comes up
again.
