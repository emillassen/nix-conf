#!/usr/bin/env bash
# -i restricts the search to named inputs, is repeatable, and is checked against
# the baseline lock so a typo costs nothing.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: -i input selection"

use_stubs nix git curl gh
sim_init
sim_input a org/a main base-a 1750000000 tip-a 1755000000
sim_input b org/b main base-b 1750000000 tip-b 1755000000
sim_input c org/c main base-c 1750000000 tip-c 1755000000
sim_write
cp "$FLAKE/flake.lock" "$TMP/before.lock"
sim_verdict <<'EOF'
exit 0
EOF

run_flake_up_safe -f "$FLAKE" -i a
assert_exit "one -i exits 0" 0
assert_eq "a moved" "tip-a" "$(lock_rev a)"
assert_eq "b did not" "base-b" "$(lock_rev b)"
assert_contains "and says the others were not selected" "$STDOUT" \
  "- b                        update available, not selected"

cp "$TMP/before.lock" "$FLAKE/flake.lock"
run_flake_up_safe -f "$FLAKE" -i a -i c
assert_exit "two -i exits 0" 0
assert_eq "a moved" "tip-a" "$(lock_rev a)"
assert_eq "c moved" "tip-c" "$(lock_rev c)"
assert_eq "b stayed" "base-b" "$(lock_rev b)"

cp "$TMP/before.lock" "$FLAKE/flake.lock"
run_flake_up_safe -f "$FLAKE" -i nope
assert_exit "an unknown input is rejected" 1
assert_contains "and the message lists what there is" "$STDERR" \
  "no input named 'nope' in the head lock"
assert_files_identical "with the lock untouched" "$TMP/before.lock" "$FLAKE/flake.lock"
