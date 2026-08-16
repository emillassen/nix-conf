---
name: test-scripts
description: >-
  This skill should be used when the user asks to "test the shell scripts",
  "extend the test suite", "add test coverage", "harden flake-up-safe",
  "find bugs in standardebooks-dl or drtv-dl", or invokes /test-scripts. It
  covers the hermetic offline bash suite in tests/ that exercises
  scripts/flake-up-safe.sh, pkgs/standardebooks-dl/standardebooks-dl.sh and
  pkgs/drtv-dl/drtv-dl.sh: how to extend it, the stub contracts it is built on,
  the defects already found and refuted, and the cleanup a pass owes. Apply it
  whenever work changes the behaviour of those three scripts, even when the
  user does not mention tests.
argument-hint: "[all|flake-up-safe|standardebooks-dl|drtv-dl] [optional focus, e.g. quota, bisect, nfo]"
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
user-invocable: true
version: 2.0.0
---

# Test and harden the shell scripts

`$ARGUMENTS`

Scope from the arguments: a script name restricts the work to that script, a
trailing phrase narrows it further, `all` or nothing means all three. An
argument naming something that is not one of the three scripts is a focus hint —
still cover all three.

Three programs, roughly 2,950 lines of non-trivial bash:

| file                             | lines | what it is                                                           |
| -------------------------------- | ----- | -------------------------------------------------------------------- |
| `scripts/flake-up-safe.sh`       | ~1200 | a search algorithm over flake input revisions                        |
| `pkgs/standardebooks-dl/…-dl.sh` | ~940  | a rate-limited catalog sync with an on-disk quota ledger             |
| `pkgs/drtv-dl/drtv-dl.sh`        | ~820  | a yt-dlp wrapper with skip detection and Jellyfin sidecar generation |

A hermetic suite for all three **already exists** in `tests/` — 43 cases, ~509
assertions, a full offline run in about 25 seconds. The job is to extend it and
find defects that are still in there. Building a second harness alongside the
first is the worst available outcome.

Shellcheck is the only other gate: at build time for the two `pkgs/` fragments,
via a pre-commit hook (`^scripts/.*\.sh$`) for `flake-up-safe.sh`. It finds
quoting bugs. It cannot tell that the bisect walks the wrong indices, that the
quota ledger loses records under concurrency, or that a trailing slash on `-d`
makes a sync re-download a library — all three of which were real.

## Prerequisites

1. `./tests/run.sh` passes before any change. A pass that starts from red cannot
   tell its own breakage from the one it is hunting.
2. `git status --porcelain -uall` is clean apart from work in progress. Note
   what was already dirty; it is not this pass's to clean up.
3. Record the wall-clock start time. Cleanup filters `/tmp` by it.
4. Read `references/harness.md` before writing a case or touching a stub.
   Nothing about the stub contracts is guessable from the file listing.
5. Read `references/findings.md` before hunting. It lists what is already fixed,
   what was refuted, and where coverage is thin.

## Non-negotiables

1. **Never touch `flake.nix`.** The suite is deliberately not wired into
   `nix flake check`; Emil decides later whether it becomes a gate. This also
   rules out adding bats or shellspec — see `references/harness.md`.
2. **Never commit.** This repo commits straight to `main` when asked, and this
   is not that ask. Leave the tree for review.
3. **Absolute scratchpad paths for temp files**, in the same command that uses
   them. The Bash tool resets cwd to the repo root every call, so a bare
   `-o out.json` lands in the repo, and `nix build -o` there creates a GC root.
4. **The suite runs fully offline.** Network access is for confirming a finding,
   never for the suite.
5. **standardebooks.org: never fire a real download.** The limit is `>35 in 30s`
   or `>100 in 6h`, sliding, on `/ebooks/*/downloads/*` only. Worse, a hidden
   `/honeypot` link in their page header is wired to fail2ban with
   `maxretry = 1, bantime = 24h` — one blind GET firewall-bans this IP for a
   day. Never follow an SE link; construct URLs only. To probe the limiter at
   all, use `curl -I`: it runs the same PHP and moves no file body.
6. **dr.dk is reachable and `-n` costs no downloads**, so live confirmation of a
   drtv-dl finding is fine. It still does not belong in the suite.
7. **Never change behaviour to make a test pass.** Where code and documentation
   disagree, work out which is wrong, fix that one, and say which in the report.

## Where a change goes

Consult before writing anything. Routing to the wrong place is the most common
way to end up with a second half-harness.

| What is being tested                                 | Where it goes                    | What it needs                           |
| ---------------------------------------------------- | -------------------------------- | --------------------------------------- |
| flake-up-safe's search, bisect, locking, reporting   | `tests/cases/flake-up-safe/`     | `sim-flake.sh`; `nix git curl gh` stubs |
| A pure function (quota maths, `media_exists`, slugs) | any case directory               | `extract_funcs`, usually no stubs       |
| standardebooks-dl catalog, ledger, pacing, layout    | `tests/cases/standardebooks-dl/` | `se.sh`; `curl date sleep` stubs        |
| Anything drtv-dl does through yt-dlp                 | `tests/cases/drtv-dl/`           | `drtv.sh`; `yt-dlp curl` stubs          |
| An assumption the suite itself rests on              | `tests/cases/harness/`           | nothing                                 |
| Proof the real derivation still works                | `tests/build-check.sh`           | the Nix daemon; run by hand             |
| A new fake for a tool                                | `tests/stubs/<tool>`             | a scenario file, never hardcoded data   |

## Procedure A: orient

1. Run `./tests/run.sh` and confirm it is green.
2. Read the "Tests" section of CLAUDE.md, then `tests/lib/harness.sh`.
3. Read `references/findings.md`, especially "Known gaps in coverage" and
   "Open questions" — that is the backlog this pass draws from.
4. Pick targets. `flake-up-safe.sh` stays the highest-value of the three: it is
   a genuine algorithm, and every input it has is stubbable, so its whole search
   runs offline and deterministically.

## Procedure B: hunt a defect

Work from a hypothesis to a failing test to a fix, in that order.

1. State the hypothesis concretely enough to be wrong: which input, which
   branch, what the wrong output is.
2. **Write the case first and watch it fail.** A finding without a failing test
   is a guess, and roughly a third of the hypotheses in the last pass were
   wrong — including several that looked obviously right.
3. Decide whether the code or the documentation is wrong. Both are dense here
   and the comments are usually accurate; when a comment and the code disagree,
   read the comment's reasoning before assuming the comment is stale.
4. Fix one behaviour at a time and re-run the affected cases after each.
5. Match the surrounding voice. These scripts are commented in a distinctive
   style that explains _why_, at high density, and so are the tests. A fix that
   arrives without that explanation is out of place. Read the neighbours first.

## Procedure C: add coverage

1. Copy the skeleton from `references/harness.md` and the closest existing case.
2. Prefer end-to-end through `run_fragment` / `run_flake_up_safe`; reach for
   `extract_funcs` when an end-to-end run would be an expensive way to check a
   subtraction.
3. Assert on stdout, stderr, exit status **and filesystem state**. Several of
   these scripts' most important guarantees are about files they leave behind or
   restore, and `assert_files_identical` is what "left exactly as found" means.
4. Assert on stub invocation counts where the claim is about cost — `builds_run`,
   `drtv_extractions`, `stub_count curl-urls`. The efficiency claims in CLAUDE.md
   are only testable that way.
5. Keep the suite offline, hermetic and under a minute.
6. Run shellcheck on everything added: it is not on the interactive PATH, so use
   `ls -d /nix/store/*shellcheck*/bin/shellcheck`. `tests/.shellcheckrc` disables
   SC1091, SC2016 and SC2034 with reasons; do not widen it without one.

## Procedure D: prove the suite catches the regression

For every fix, revert it, run the matching case, confirm it fails, restore.
Script the loop rather than doing it by eye.

**This step is not optional and not inferable.** Two of the last pass's fifteen
fixes had tests that did _not_ catch the reverted bug — one because a second
normalisation masked it, one because the race was timing-dependent — and both
looked obviously covered. "The test clearly exercises that line" is exactly the
reasoning that produced those two.

## Procedure E: keep the documentation true

CLAUDE.md documents all three scripts in unusual detail and each script carries
its own usage block. Behaviour changes update both in the same pass; stale docs
here are loud. After editing CLAUDE.md run
`/nix/store/*prettier*/bin/prettier --write CLAUDE.md` — `nix flake check`
discards the hook's auto-fix and only prints a diff.

After touching a `pkgs/**/*.sh`, run `./tests/build-check.sh`: those builds are
the only place either script is linted. Run `nix flake check` once at the end —
it evaluates the whole system and is slow.

## Procedure F: clean up

Run before writing the report, not after.

1. `git status --porcelain -uall` shows only intended files. No `result` or
   `result-*` symlinks anywhere; no `.bak`, `.orig` or `__pycache__` under
   `tests/`.
2. Empty the scratchpad.
3. `scripts/check-leftovers.sh --since '<session start>'` lists what this
   session left in `/tmp`; add `--remove` to delete exactly that set. It refuses
   to delete by pattern alone, and never touches `tmp.XXXXXXXXXX` names, because
   Emil runs these scripts for real and one such directory turned out to hold a
   genuine sitemap from a killed run. Report anything unattributable instead of
   deleting it.
4. Re-run `./tests/run.sh` and confirm the run itself adds nothing to `/tmp`.

## Procedure G: report, then update this skill

The report covers: what was added and what it covers; each finding with a
severity and a reproduction; what was fixed; what was left alone and why; and
**which hypotheses turned out to be wrong** — that last part is worth as much as
the findings, and it is the part that stops the next pass re-chasing them.

Then update this skill in the same pass:

- fold new findings into `references/findings.md`, and strike from "Known gaps"
  whatever is now covered;
- add anything that cost a debugging round to `references/bash-traps.md`;
- record new helpers or stub behaviour in `references/harness.md`;
- correct the case and assertion counts in this file.

Skipping this is the quiet failure mode: everything still passes, and the next
pass pays the same debugging cost over again.

## Cross-cutting gotchas

**`writeShellApplication` prepends its runtimeInputs to PATH.** No stub can
shadow the real `yt-dlp` or `curl` inside a built derivation. That is why the
suite runs the raw fragment under a preamble it synthesizes itself, and why the
real-derivation check lives in `tests/build-check.sh`.

**The two `pkgs/` fragments have no shebang and no `set` line.** Running one with
plain `bash file.sh` silently drops errexit, nounset and pipefail — exactly the
class of bug worth hunting. `tests/cases/harness/00-preamble.sh` guards that
assumption in both directions; keep it passing.

**Always stub `gh`.** The real one is authenticated and will reach the network.
`flake-up-safe.sh` prefers it whenever it is on PATH.

**A skipped case reads as a pass.** Never skip for a missing tool; use
`require_tool`, which falls back to the Nix store.

**A green suite proves nothing about a route it never takes.** Cases redirect
stdout to a file, so every TTY-only branch is unexercised. Check
`references/findings.md` before claiming coverage.

The remaining traps — bash 5.2's `&` in a substitution replacement, quote
removal in the pattern half, `grep -c` exiting 1 while printing 0, and six more,
each of which cost a round — are in `references/bash-traps.md`. Read it before
debugging anything that looks impossible.

## Reference files

- **`references/harness.md`** — layout, helper API, assertions, scenario
  builders, stub contracts, how to add a stub, and why not bats.
- **`references/findings.md`** — what is fixed (with the case that catches each
  regression), what was refuted, known gaps, open questions.
- **`references/bash-traps.md`** — the traps that have already cost a round.
- **`scripts/check-leftovers.sh`** — report or remove a session's `/tmp` scratch.
