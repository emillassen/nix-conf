#!/usr/bin/env bash
# -t names the thing to build outright, which makes a -H alongside it
# meaningless. Silently ignoring one of two contradictory flags is the kind of
# thing you only notice after a two-hour run built the wrong host.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: -t together with -H"

use_stubs nix git curl gh
sim_init
sim_input a org/a main base-a 1750000000 tip-a 1755000000
sim_write
sim_verdict <<'EOF'
exit 0
EOF

run_flake_up_safe -f "$FLAKE" -t devilutionx -H fw13
assert_exit "refuses the contradiction" 1
assert_contains "and says why" "$STDERR" "--target and --host cannot be combined"

# -t on its own still works, and is taken as an attr of this flake.
run_flake_up_safe -f "$FLAKE" -t devilutionx -n
assert_exit "-t alone is fine" 0
assert_contains "the target is this flake's attr" "$STDOUT" "target:   $FLAKE#devilutionx"
