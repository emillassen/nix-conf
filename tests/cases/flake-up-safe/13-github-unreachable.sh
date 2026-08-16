#!/usr/bin/env bash
# When GitHub is unreachable or rate-limited, every day: candidate resolves to
# nothing. The walk then finds nothing — but "nothing builds" and "nothing could
# be asked about" are different answers, and reporting a build verdict about
# revisions that were never built is wrong.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: GitHub unreachable during a bisect"

use_stubs nix git curl gh
sim_init
T=1767225600
BASE_REV="$(hexrev base)"
sim_input hm org/hm main "$BASE_REV" "$((T - 10 * 86400))" "$(idxrev 0)" "$T"
sim_write
sim_gh_dead org/hm

sim_verdict <<EOF
grep -qx "hm=$BASE_REV" && exit 0
exit 1
EOF

run_flake_up_safe -f "$FLAKE" -d 5

assert_exit "exits 0" 0
assert_contains "says candidates could not be resolved" "$STDOUT" "could not resolve"
assert_eq "the input stays at its baseline" "$BASE_REV" "$(lock_rev hm)"

# Only the tip was ever built (the baseline, and the tips trial). Nothing else
# could even be named, so nothing else was tried.
assert_eq "two builds" 2 "$(builds_run)"

# The distinction the report has to make.
assert_not_contains "does not claim a build verdict it never reached" "$STDOUT" \
  "No revision newer than the baseline builds"
assert_contains "blames the network instead" "$STDOUT" \
  "No candidate revision could be resolved"
