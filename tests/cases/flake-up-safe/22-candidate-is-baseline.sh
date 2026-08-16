#!/usr/bin/env bash
# A daily walk's oldest candidates run right down to the day the baseline was
# locked, so one of them resolves to the baseline revision itself. That
# revision's verdict is pre-seeded as ok and has no recorded timestamp, which
# raises the question of whether the "is this newer than the baseline" test can
# be fooled by the `:-0` fallback. It cannot: revision equality is checked
# first, and nothing else ever lands in REV_VERDICT without also landing in
# REV_TS.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: a candidate that is the baseline"

use_stubs nix git curl gh
sim_init
T=1767225600
BASE_REV="$(hexrev base)"
sim_input hm org/hm main "$BASE_REV" "$((T - 3 * 86400))" "$(idxrev 0)" "$T"
sim_write

# Yesterday's commit is broken; the day before that *is* the baseline commit.
sim_gh_day org/hm "$(date -u -d "@$((T - 86400))" +%F)" "$(idxrev 1)" "$((T - 86400))"
sim_gh_day org/hm "$(date -u -d "@$((T - 2 * 86400))" +%F)" "$BASE_REV" "$((T - 3 * 86400))"

sim_verdict <<EOF
grep -qx "hm=$BASE_REV" && exit 0
exit 1
EOF

run_flake_up_safe -f "$FLAKE"

assert_exit "exits 0" 0
assert_contains "the baseline candidate is answered from the pre-seeded verdict" \
  "$STDOUT" "(already known: ok)"
assert_contains "and is not mistaken for an improvement" "$STDOUT" \
  "nothing newer than the baseline builds; staying at baseline"
assert_eq "the lock keeps the baseline revision" "$BASE_REV" "$(lock_rev hm)"
# baseline + tips + the one broken day. The baseline candidate costs nothing.
assert_eq "three builds" 3 "$(builds_run)"
