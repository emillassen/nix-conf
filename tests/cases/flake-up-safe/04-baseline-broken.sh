#!/usr/bin/env bash
# Property 4: if the baseline itself does not build, nothing can be concluded —
# exit 1, the working tree's flake.lock byte-identical to what the run started
# with (which is *not* the baseline: the tree may be dirty), and logs retained.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: baseline does not build"

use_stubs nix git curl gh
sim_init
sim_input a org/a main base-a 1750000000 tip-a 1755000000
sim_input b org/b main base-b 1750000000 tip-b 1755000000
sim_write

# A dirty working tree: the lock on disk is neither HEAD's nor any tip's. It is
# what must come back untouched.
sim_rev hand-edited-a 1752000000
jq '.nodes.a.locked.rev = "hand-edited-a"' "$FLAKE/flake.lock" >"$TMP/dirty.lock"
cp "$TMP/dirty.lock" "$FLAKE/flake.lock"

sim_verdict <<'EOF'
echo "error: builder for '/nix/store/x.drv' failed with exit code 1" >&2
exit 1
EOF

run_flake_up_safe -f "$FLAKE"

assert_exit "exits 1" 1
assert_contains "names the baseline as the problem" "$STDERR" \
  "the head baseline does not build on its own"
assert_contains "keeps the logs" "$STDERR" "logs kept in"
assert_contains "says the lock was restored" "$STDERR" "flake.lock restored"
assert_files_identical "flake.lock byte-identical to the dirty tree's" \
  "$TMP/dirty.lock" "$FLAKE/flake.lock"
assert_eq "only the baseline was ever built" 1 "$(builds_run)"
