#!/usr/bin/env bash
# Where a daily search gets its candidates, and what it may claim about them.
#
# The days run from the day before the tip back to the baseline's own day. They
# used to be made by subtracting whole days from the tip's timestamp, which keeps
# the tip's time of day: with the tip at 10:00 and the baseline at 15:00, the
# baseline's day came out as 10:00 that day, "older than the baseline", and was
# never a candidate - though the commits after 15:00 on it are newer than it.
#
# And a candidate whose lookup failed used to count as one that failed to build:
# it moved the walk's bound past itself, so the run could announce the newest
# working candidate with a newer one never even named.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: daily candidates"

use_stubs nix git curl gh

# --- the baseline's own day is a candidate ---------------------------------------
sim_init
BASE_TS="$(date -u -d '2026-01-01T15:00:00Z' +%s)"
TIP_TS="$(date -u -d '2026-01-03T10:00:00Z' +%s)"
BASE="$(hexrev base)" TIP="$(hexrev tip)"
JAN2="$(hexrev jan2)" JAN1="$(hexrev jan1-evening)"
sim_input hm org/hm main "$BASE" "$BASE_TS" "$TIP" "$TIP_TS"
sim_write
sim_gh_day org/hm 2026-01-02 "$JAN2"
sim_gh_day org/hm 2026-01-01 "$JAN1" "$(date -u -d '2026-01-01T20:00:00Z' +%s)"
sim_verdict <<EOF
combo="\$(cat)"
grep -qx "hm=$TIP" <<<"\$combo" && exit 1
grep -qx "hm=$JAN2" <<<"\$combo" && exit 1
exit 0
EOF
run_flake_up_safe -f "$FLAKE" -d 5
assert_exit "exits 0" 0
# A probe line - four spaces and the label at the start of a line - not the
# "↻ hm 2026-01-01 → …" summary above, which carries the same date.
assert_eq "the baseline's day is searched" 1 "$(grep -c '^    2026-01-01 ' <<<"$STDOUT")"
assert_eq "and its evening commit, newer than the baseline, is taken" "$JAN1" "$(lock_rev hm)"

# --- an unresolved candidate is not a failed one -----------------------------------
sim_init
rm -f "$STUBLOG/builds.log"
T=1767225600
BASE="$(hexrev base2)" TIP="$(hexrev tip2)" OLDER="$(hexrev two-days-back)"
sim_input hm org/hm main "$BASE" "$((T - 10 * 86400))" "$TIP" "$T"
sim_write
# Yesterday's lookup fails; the day before resolves and builds.
printf 'repos/org/hm/commits?sha=*until=%s*\t-\n' "$(date -u -d "@$((T - 86400))" +%F)" >>"$GH_MAP"
sim_gh_day org/hm "$(date -u -d "@$((T - 2 * 86400))" +%F)" "$OLDER"
sim_verdict <<EOF
grep -qx "hm=$TIP" && exit 1
exit 0
EOF
run_flake_up_safe -f "$FLAKE" -d 5
assert_exit "a partly unresolved search: exits 0" 0
assert_eq "it settles on what it could see" "$OLDER" "$(lock_rev hm)"
assert_contains "but says a newer candidate went unchecked" "$STDOUT" \
  "1 newer candidate(s) could not be resolved"
