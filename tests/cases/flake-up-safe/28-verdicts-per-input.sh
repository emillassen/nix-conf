#!/usr/bin/env bash
# REV_VERDICT caches a bisect's verdict by revision alone, and it used to live
# for the whole run. Two inputs that track the same repository - nixpkgs and
# nixpkgs-stable do - can meet the same candidate revision, and the second then
# took the first one's verdict on it without a trial: a verdict reached for a
# different input, under a different set of pins. Here `a` at R breaks and `b`
# at R builds, and b was held back at its baseline on a's say-so.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: a bisect verdict belongs to its own input"

use_stubs nix git curl gh
sim_init
T=1767225600
DAY="$(date -u -d "@$((T - 86400))" +%F)"
BASE_A="$(hexrev base-a)" BASE_B="$(hexrev base-b)"
TIP_A="$(hexrev tip-a)" TIP_B="$(hexrev tip-b)"
R="$(hexrev shared-yesterday)"
sim_input a org/shared main "$BASE_A" "$((T - 10 * 86400))" "$TIP_A" "$T"
sim_input b org/shared main "$BASE_B" "$((T - 10 * 86400))" "$TIP_B" "$T"
sim_write
# One commit for that day on the shared repository, whichever input asks.
sim_gh_day org/shared "$DAY" "$R"

sim_verdict <<EOF
combo="\$(cat)"
grep -qx "a=$TIP_A" <<<"\$combo" && exit 1
grep -qx "b=$TIP_B" <<<"\$combo" && exit 1
grep -qx "a=$R" <<<"\$combo" && exit 1
exit 0
EOF

run_flake_up_safe -f "$FLAKE" -d 2

assert_exit "exits 0" 0
assert_eq "a, which breaks at R, stays at its baseline" "$BASE_A" "$(lock_rev a)"
assert_eq "b, which builds at R, is pinned to it" "$R" "$(lock_rev b)"
assert_contains "b's own trial at R was run" "$(build_combos)" "a=$BASE_A,b=$R"
assert_not_contains "rather than a's verdict reused" "$STDOUT" "(already known: bad)"
