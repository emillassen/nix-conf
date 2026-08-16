# Bash and tooling traps

Each of these cost a debugging round in a previous pass. Two of them were live
bugs in the scripts, not just test-writing mistakes. Add to the list whenever
something costs a round again.

## Parameter expansion

**`&` in the replacement half of `${var//pat/rep}` means "the matched text"** as
of bash 5.2, so `${s//&amp;/&}` is a no-op. Write `\&`. This was live in
standardebooks-dl: every title with an ampersand was filed under
`Dr. Jekyll &amp; Mr. Hyde`.

**Quotes are removed from the _pattern_ half** before matching, so
`${url//Format='png'/Format='jpg'}` looks for `Format=png` without the
apostrophes and never matches. Quote the whole side:
`${url//"Format='png'"/"Format='jpg'"}`. This was live in drtv-dl: every
replaced poster stayed a PNG under a `.jpg` name.

**A trailing slash makes a strip prefix match nothing.** `${x#"$dest"/}` with
`dest=lib/` looks for `lib//`. Build the prefix once, defensively:

```bash
dest_prefix="$dest"
while [[ "$dest_prefix" == */ ]]; do dest_prefix="${dest_prefix%/}"; done
dest_prefix="$dest_prefix/"
```

That form also survives `-d //` and leaves `/` as itself. Audit every strip in
all three scripts when touching this.

## Shell mechanics

**`$(run_flake_up_safe …)` throws the result away.** The run helpers set
`STATUS`, `STDOUT` and `STDERR` as globals; a command substitution runs them in a
subshell. Have a helper set a variable instead of printing one.

**A scenario script that reads stdin can only read it once.** Two successive
`grep -q` calls in a `sim_verdict` body: the first consumes everything, the
second sees an empty stream and the verdict is silently wrong. Start with
`combo="$(cat)"`.

**`grep -c` prints `0` and exits 1** on no match, so `grep -c … || echo 0`
prints "0\n0" and every numeric assertion against it fails confusingly. Count
with `awk` in helpers.

**A comment line beginning `# shellcheck …` is parsed as a directive**, even in
prose. `# shellcheck runs for those two scripts.` is an SC1073 error. Reword.

**Redirect `TMPDIR`, do not just clean up.** Programs under test make their own
scratch directories, and flake-up-safe keeps its on purpose whenever a run fails.
`test_init` points `TMPDIR` inside the case directory so all of it goes at once.

## Tooling

**`unzip`, `shellcheck` and `flock` are not on the interactive PATH here.** Use
`require_tool`, which falls back to `/nix/store/*-<tool>-*/bin/<tool>`. Never
skip a case for a missing tool: a skipped case reads as a pass, which is worse
than a red one.

**yt-dlp names its leftovers after the _final_ filename** — `Ep.mp4.part`,
`Ep.mp4.ytdl`, `Ep.f137.mp4` — which is exactly why `media_exists`'
single-token-extension rule works. A fixture named `Ep.part` tests nothing that
happens in reality.

**Real yt-dlp applies `--parse-metadata` before writing the info.json**, so the
sidecars see rewritten fields. A stub that writes the raw scenario object will
disagree with the script over every title.

**Command substitution mangles binary.** A curl stub that does
`body="$(cat file)"` cannot serve a zip. Copy the file through instead.

**`nix build -o` inside the repo creates a GC root.** Any `-o` goes in the
scratchpad. `tests/build-check.sh` already does this correctly; copy it rather
than improvising.

**prettier formats CLAUDE.md** via the pre-commit hook, and `nix flake check`
discards a hook's auto-fix and only prints the diff. Run
`/nix/store/*prettier*/bin/prettier --write CLAUDE.md` directly instead of
applying a printed diff by hand.
