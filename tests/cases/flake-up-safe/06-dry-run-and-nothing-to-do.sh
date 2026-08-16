#!/usr/bin/env bash
# Property 6: -n builds nothing and leaves flake.lock untouched. Same for a lock
# that is already at every tip — nothing was verified, so nothing is written.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: dry run and nothing to search"

use_stubs nix git curl gh
sim_init
sim_input a org/a main base-a 1750000000 tip-a 1755000000
sim_input b org/b main base-b 1750000000 tip-b 1755000000
sim_write
cp "$FLAKE/flake.lock" "$TMP/before.lock"
sim_verdict <<'EOF'
exit 0
EOF

run_flake_up_safe -f "$FLAKE" -n
assert_exit "-n exits 0" 0
assert_contains "-n lists the updates" "$STDOUT" "2 input(s) have updates"
assert_eq "-n builds nothing" 0 "$(builds_run)"
assert_eq "-n evaluates nothing" 0 "$(stub_count nix path-info)"
assert_files_identical "-n leaves flake.lock alone" "$TMP/before.lock" "$FLAKE/flake.lock"

# Now a lock that is already current: same guarantee, different reason.
rm -f "$STUBLOG/builds.log" "$STUBLOG/nix.log"
sim_init
sim_input a org/a main same-a 1755000000 same-a 1755000000
sim_input b org/b main same-b 1755000000 same-b 1755000000
sim_write
sim_verdict <<'EOF'
exit 0
EOF
cp "$FLAKE/flake.lock" "$TMP/before2.lock"

run_flake_up_safe -f "$FLAKE"
assert_exit "nothing-to-search exits 0" 0
assert_contains "says so" "$STDOUT" "Nothing to search — flake.lock untouched."
assert_eq "builds nothing" 0 "$(builds_run)"
assert_files_identical "leaves flake.lock alone" "$TMP/before2.lock" "$FLAKE/flake.lock"
