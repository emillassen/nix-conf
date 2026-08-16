#!/usr/bin/env bash
# Property 11a: `--linear N` means "the first N candidates are checked one at a
# time, then the stride starts doubling". Both --help and CLAUDE.md say so, and
# in particular say that 0 skips from the start.
#
# This pins the whole walk, because the walk is the part of the bisect that
# needs no monotonicity assumption and is therefore the part worth being exact
# about.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: the --linear walk"

use_stubs nix git curl gh
sim_init
T=1767225600 # 2026-01-01
BASE_REV="$(hexrev base)"
# The baseline sits far enough back that --max-days, not the baseline, is what
# ends the candidate list: 40 candidates exactly, the tip plus 39 days.
sim_input hm org/hm main "$BASE_REV" "$((T - 90 * 86400))" "$(idxrev 0)" "$T"
sim_write
for i in $(seq 1 45); do
  sim_gh_day org/hm "$(date -u -d "@$((T - i * 86400))" +%F)" "$(idxrev "$i")" "$((T - i * 86400))"
done

# Nothing in the whole window builds, so the walk runs to its end and every
# index it visits is visible in the output.
sim_verdict <<EOF
grep -qx "hm=$BASE_REV" && exit 0
exit 1
EOF

# The first `n` indices of a probe sequence — the walk, before the narrowing
# pass that follows it.
first_n() { tr ' ' '\n' <<<"$1" | head -n "$2" | tr '\n' ' ' | sed 's/ $//'; }

# Sets SEQ rather than printing it: run_flake_up_safe leaves its output in
# globals, and a command substitution would run the whole thing in a subshell
# and throw them away.
SEQ=""
walk_for() {
  local linear="$1"
  rm -f "$STUBLOG"/curl-n-* "$STUBLOG/builds.log"
  run_flake_up_safe -f "$FLAKE" -d 40 -l "$linear"
  SEQ="$(probed_indices "$STDOUT")"
}

# --linear 0: no linear prefix at all. Index 0 is always visited (it is the tip,
# and re-testing it is free), and the stride doubles from there.
walk_for 0
assert_eq "--linear 0 skips from the start" "0 2 6 14 30" "$(first_n "$SEQ" 5)"

# 1 candidate one at a time is the same walk as 0: you cannot visit fewer than
# the one you start on.
walk_for 1
assert_eq "--linear 1 matches --linear 0" "0 2 6 14 30" "$(first_n "$SEQ" 5)"

walk_for 2
assert_eq "--linear 2 checks two, then doubles" "0 1 3 7 15 31" "$(first_n "$SEQ" 6)"

walk_for 7
assert_eq "--linear 7 (the default) checks seven" \
  "0 1 2 3 4 5 6 8 12 20 36" "$(first_n "$SEQ" 11)"

walk_for 10
assert_eq "--linear 10 checks ten" \
  "0 1 2 3 4 5 6 7 8 9 11 15 23 39" "$(first_n "$SEQ" 14)"

# And the walk really did run out of candidates rather than stopping early:
# nothing was pinned.
assert_contains "nothing pinned when the whole window is broken" "$STDOUT" \
  "nothing newer than the baseline builds; staying at baseline"
