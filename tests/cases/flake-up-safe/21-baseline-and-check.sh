#!/usr/bin/env bash
# --baseline worktree for a checkout with no committed lock, and -k making
# `nix flake check` part of the verdict: a set can build and still be rejected.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: --baseline worktree and -k"

use_stubs nix git curl gh
sim_init
sim_input a org/a main base-a 1750000000 tip-a 1755000000
sim_input b org/b main base-b 1750000000 tip-b 1755000000
sim_write
cp "$FLAKE/flake.lock" "$TMP/before.lock"
sim_verdict <<'EOF'
exit 0
EOF

# No lock in HEAD at all.
rm -f "$SIM/head.lock"
run_flake_up_safe -f "$FLAKE" -n
assert_exit "--baseline head has nothing to read" 1
assert_contains "and suggests the way out" "$STDERR" \
  "could not read flake.lock from HEAD (try --baseline worktree)"

run_flake_up_safe -f "$FLAKE" -b worktree -n
assert_exit "--baseline worktree reads the tree instead" 0
assert_contains "reports the baseline it used" "$STDOUT" "baseline: worktree"

# -k: b's tip builds but does not pass `nix flake check`, so it is held back on
# the check's word rather than the build's.
sim_check <<'EOF'
grep -qx 'b=tip-b' && exit 1
exit 0
EOF
run_flake_up_safe -f "$FLAKE" -b worktree -k --no-bisect
assert_exit "exits 0" 0
assert_contains "the check failure is reported as one" "$STDOUT" "flake check failed"
assert_eq "a still reached its tip" "tip-a" "$(lock_rev a)"
assert_eq "b was held back by the check" "base-b" "$(lock_rev b)"
