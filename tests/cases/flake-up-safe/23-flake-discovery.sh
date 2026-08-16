#!/usr/bin/env bash
# Which flake the run operates on, when -f does not say. Every other case passes
# -f, so the whole discovery chain — the script's own repo, then $NH_FLAKE, then
# a walk up from $PWD — has never run under test, and it is the one decision in
# the script that can send a two-hour run at the wrong flake entirely.
#
# The two "nothing found" legs walk up past $TMP to /, so they assume no ancestor
# of the temp directory carries a flake.nix. That is a loud failure if it is ever
# false, not a silent one: the assertion names the directory it settled on.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: finding the flake without -f"

use_stubs nix git curl gh
sim_init
sim_input a org/a main base-a 1750000000 tip-a 1755000000
sim_write
sim_verdict <<'EOF'
exit 0
EOF

# A checkout: the script sits in scripts/ inside the flake it belongs to.
mkdir -p "$FLAKE/scripts" "$FLAKE/nixos"
cp "$FLAKE_UP_SAFE" "$FLAKE/scripts/flake-up-safe.sh"

# A second flake for $NH_FLAKE to point at, so "the script's own repo wins" is a
# choice between two real answers rather than between one and nothing.
DECOY="$TMP/decoy"
mkdir -p "$DECOY"
echo '{ }' >"$DECOY/flake.nix"
cp "$FLAKE/flake.lock" "$DECOY/flake.lock"

export NH_FLAKE="$DECOY"

FLAKE_UP_SAFE="$FLAKE/scripts/flake-up-safe.sh"
run_flake_up_safe -n
assert_exit "a script in a checkout needs no -f" 0
assert_contains "and picks the flake it sits in, over \$NH_FLAKE" "$STDOUT" "flake:    $FLAKE"

# Installed into the store by a Nix wrapper, the script sits in a bin directory
# with no flake anywhere above it, which is exactly what $NH_FLAKE is the answer
# to — the rest of the system already agrees that is "the" flake.
mkdir -p "$TMP/store/bin"
cp "$FLAKE_UP_SAFE" "$TMP/store/bin/flake-up-safe"
FLAKE_UP_SAFE="$TMP/store/bin/flake-up-safe"
run_flake_up_safe -n
assert_exit "an installed copy falls back to \$NH_FLAKE" 0
assert_contains "and uses it" "$STDOUT" "flake:    $DECOY"

# With neither, the directory the user is standing in decides — and it is a walk
# up, not just the directory itself, so working two levels down still finds it.
unset NH_FLAKE
mkdir -p "$FLAKE/nixos/common"
RUN_CWD="$FLAKE/nixos/common" run_flake_up_safe -n
assert_exit "\$PWD is the last resort" 0
assert_contains "and the walk climbs to the flake root" "$STDOUT" "flake:    $FLAKE"

# Nothing anywhere: say so, and name the flag that fixes it.
mkdir -p "$TMP/nowhere"
RUN_CWD="$TMP/nowhere" run_flake_up_safe -n
assert_exit "no flake at all is fatal" 1
assert_contains "and points at -f" "$STDERR" "no flake.nix found (pass --flake DIR)"

# An explicit -f is checked before anything else is done with it: a typo must not
# turn into a walk up from somewhere unrelated.
run_flake_up_safe -f "$TMP/no-such-dir" -n
assert_exit "-f at a missing directory is fatal" 1
assert_contains "and names it" "$STDERR" "no such directory: $TMP/no-such-dir"

# A directory that is a flake but has no lock has nothing to search against.
run_flake_up_safe -f "$TMP/nowhere" -n
assert_exit "-f at a lockless directory is fatal" 1
assert_contains "and says which file is missing" "$STDERR" "$TMP/nowhere/flake.lock not found"
