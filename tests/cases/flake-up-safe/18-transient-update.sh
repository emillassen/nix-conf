#!/usr/bin/env bash
# A network blip while resolving an input says nothing about the input. Builds
# already get exactly one retry for that reason; composition used to get none,
# so a single dropped packet an hour into a multi-hour run threw the whole run
# away. It gets the same single retry now — and a failure that is not transient,
# or one that survives the retry, still stops the run with the lock restored.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: a transient nix flake update failure"

use_stubs nix git curl gh
sim_init
sim_input a org/a main base-a 1750000000 tip-a 1755000000
sim_input b org/b main base-b 1750000000 tip-b 1755000000
sim_write
cp "$FLAKE/flake.lock" "$TMP/before.lock"
sim_verdict <<'EOF'
exit 0
EOF

# One blip during the very first resolve, then the network is back.
printf 'a\n' >"$SIM/update-fail-once"

run_flake_up_safe -f "$FLAKE"
assert_exit "the run survives the blip" 0
assert_contains "and says it retried" "$STDERR" "network trouble resolving inputs, retrying once"
assert_eq "a still reached its tip" "tip-a" "$(lock_rev a)"
assert_eq "b still reached its tip" "tip-b" "$(lock_rev b)"

# A failure that outlasts the retry is still fatal, and still leaves the tree
# exactly as it was found.
cp "$TMP/before.lock" "$FLAKE/flake.lock"
rm -f "$SIM/update-fail-once"
printf 'a\n' >"$SIM/update-fail"
run_flake_up_safe -f "$FLAKE"
assert_exit "a persistent failure stops the run" 1
assert_contains "and says what failed" "$STDERR" "nix flake update failed"
assert_files_identical "flake.lock untouched" "$TMP/before.lock" "$FLAKE/flake.lock"
