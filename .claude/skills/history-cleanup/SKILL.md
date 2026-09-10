---
name: history-cleanup
description: >-
  This skill should be used when the user asks to "clean up my zsh history",
  "clean my shell history", remove commands mentioning some topic or app from
  history, strip API keys/tokens/passwords out of history, drop commands that
  no longer work, or de-duplicate history. It parses ~/.zsh_history into whole
  entries, classifies dead commands, redacts secret values while keeping the
  command readable, optionally collapses duplicates, and writes atomically with
  a backup and a zsh round-trip verification.
argument-hint: "[topic to purge] [--dedup] [--apply]"
---

# zsh history cleanup

Run `scripts/clean-history.py`. It reports by default and only writes with
`--apply`, so the judgement calls stay with the user.

**Never filter this file line-wise.** `grep -v`, `sed -i` and friends will cut
multi-line commands in half and leave the tail behind as a bogus entry. The
script exists because the format has sharp edges (see _Format facts_).

## Workflow

1. **Report.** `scripts/clean-history.py` (add `--drop-pattern RE` for each
   topic the user named, e.g. `--drop-pattern 'cookies'`). Nothing is written.
2. **Review the buckets with the user.** Present counts and the frequency
   table. `unresolved-args` is the bucket that needs a human — see below.
3. **Apply** with the buckets they approved:
   `--apply --drop-bucket unresolved-bare --drop-bucket not-a-command ...`
4. **Report back**: what went, what was redacted, and which secrets to rotate.

## The buckets

| bucket            | what it is                                              | default judgement                |
| ----------------- | ------------------------------------------------------- | -------------------------------- |
| `pattern:<re>`    | matched a `--drop-pattern` the user asked for           | drop                             |
| `unresolved-bare` | unknown command, no args or just `--help`               | drop — a removed alias or a typo |
| `unresolved-args` | unknown command **with real arguments**                 | **ask**                          |
| `not-a-command`   | pasted prose, program output, bracketed-paste artifacts | drop                             |
| `empty`           | blank entries                                           | drop                             |

`unresolved-args` is genuinely ambiguous: an uninstalled-but-real tool
(`terraform init`, `immich upload --recursive 2024`) looks the same as a typo.
Use the frequency table the report prints:

- **high count + `bare`** → an alias the user deleted from their config. Dead;
  drop it. Confirm by grepping their dotfiles/nix config for the name.
- **low count + `with-args`** → a real tool that is merely not installed today.
  Ask before dropping; the command line itself may be worth keeping.
- **bare name or `--help` only** → a one-off "is this installed?" probe. Junk.

Rescue or condemn individual names with `--keep-command NAME` /
`--drop-command NAME` rather than hand-editing the file.

## Secrets

Redaction is always on and **keeps the command**, replacing only the value:

```
immich login http://10.0.0.5:2283/api YJEgVvQq1WtTyr…   ->   … <REDACTED:api-key>
curl 'https://x/f?token=ac9f2122fbff…'                  ->   …?token=<REDACTED:url-param>
```

Three layers, cheapest and safest first: vendor-prefixed tokens (`sk-ant-`,
`ghp_`, `AKIA…`, JWTs, …); labelled values (`--token=`, `API_KEY=`,
`?token=`, `Authorization: Bearer`, `https://user:pass@host`); and, only for
entries that are _about_ authentication, a high-entropy scan that catches bare
positional keys like the `immich login` case. That auth-context gate matters —
an unguarded entropy scan shreds nix store paths, hashes and filenames. Nix
store paths, SRI hashes, UUIDs, git SHAs, ssh public keys and anything ending
in a file extension are excluded outright. Use `--no-entropy` to keep only the
first two layers.

**Two things to tell the user afterwards:**

- **The backup still contains the original secrets.** It is written `0600`, but
  it is plaintext. Delete it (`shred -u`) once they are happy, or move it
  somewhere encrypted.
- **Redaction is not rotation.** Any key that reached the history should be
  rotated — assume it leaked. Report which ones by their masked preview
  (`YJEg…Cwmw`), never the full value.

The report deliberately prints only masked previews, so it is safe to keep.

## Duplicates

Off by default; `--dedup` enables it, `--dedup-keep first|last` (default
`last`). Exact matches only, compared on the command with the timestamp
stripped — never fuzzy.

Recommended: **dedup, keeping the newest.** `HIST_IGNORE_DUPS` only suppresses
_consecutive_ repeats, so a long history is mostly `ls` / `cd ..` / `clear`;
collapsing typically removes 70-85% of entries and makes Ctrl-R dramatically
better. Keeping the newest preserves "when did I last use this", which is what
recall actually needs.

It runs _after_ redaction, so two logins that differed only by a rotated key
collapse into one entry.

Skip it (or use `--dedup-keep first`) when the user wants history as a
_record_ rather than a lookup table — reconstructing what they did during an
incident, or auditing how often something ran. Dedup keeps one copy of every
distinct command, so nothing is lost except repetition counts and older
timestamps; that is the whole of the trade.

## Format facts

- **Multi-line entries.** A line ending in a backslash continues into the next.
  **Any** trailing backslash continues it, not an odd number: a command that
  itself ended in `\` is stored as `\\` and still continues. Verified with
  `fc -R`/`fc -l`.
- **Mixed timestamps.** `EXTENDED_HISTORY` writes `: <epoch>:<elapsed>;cmd`;
  without it the line is the bare command. One file routinely holds both,
  because the option changed over time. Match the prefix optionally.
- **Abbreviations are invisible to `whence`.** zsh-abbr expands at the prompt
  and can push the _unexpanded_ form into history, so `fus` looks dead while
  working fine. The script reads `~/.config/zsh-abbr/user-abbreviations`; check
  it before declaring a short name dead.
- **`VAR=val cmd` and bare `VAR=val`.** Strip assignment prefixes before taking
  the command word, and keep bare assignments — they are valid shell.
- **`#` is not a comment** unless `interactive_comments` is set (the report says
  which). A pasted `#`-headed block whose later lines are real commands is kept.
- **Non-UTF-8 bytes.** These files often hold latin-1 leftovers, so plain `grep`
  decides the file is binary and prints _nothing_. Use `grep -a` when spot-
  checking, or you will misread a working file as empty.

## Live-shell hazard

`SHARE_HISTORY` means the user's other terminals append while the script runs;
the file grows mid-analysis. The script re-reads at write time and swaps
atomically (`os.replace`), so this is safe, but tell the user that a shell open
_before_ the rewrite may re-append a few entries from its in-memory buffer when
it exits. For a fully clean result they should close other terminals first, or
run `fc -R` afterwards.

## Verification

`--apply` re-reads the result with `zsh -f -i -c 'fc -R …; fc -l -n …'` and
compares the entry count to what it intended to keep, printing `OK` or
`MISMATCH`. `MISMATCH` means the continuation encoding was mangled — restore
the backup. To double-check by hand that nothing was rewritten:

```sh
comm -23 <(grep -av REDACTED cleaned | sort -u) <(grep -a "" backup | sort -u)
```

Empty output means every surviving line is byte-identical to the original.
