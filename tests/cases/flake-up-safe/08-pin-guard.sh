#!/usr/bin/env bash
# Property 8: pin_input's guard. `--override-input` implying
# --no-write-lock-file has been proposed upstream more than once; if a future
# nix adopts it, every bisect verdict would silently be a verdict on the
# unpinned lock. The run must stop dead instead.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: pin that does not land aborts the run"

use_stubs nix git curl gh
sim_init
T=1767225600
BASE_REV="$(hexrev base)"
sim_input nixpkgs NixOS/nixpkgs nixos-unstable "$BASE_REV" "$T" "$(idxrev 0)" "$((T + 10 * 86400))"
sim_write
cp "$FLAKE/flake.lock" "$TMP/before.lock"
sim_channel_releases nixos/unstable/ 26.05 pre <<EOF
9000	$(idxrev 0)	$((T + 10 * 86400))
8000	$(idxrev 1)	$((T + 5 * 86400))
EOF
sim_verdict <<EOF
grep -qx 'nixpkgs=$BASE_REV' && exit 0
exit 1
EOF
# This is the future where --override-input stops writing the lock.
touch "$SIM/pin-noop"

run_flake_up_safe -f "$FLAKE"

assert_exit "exits 1" 1
assert_contains "says the pin did not land" "$STDERR" "nix did not write the pin for nixpkgs"
assert_contains "restores the lock" "$STDERR" "flake.lock restored"
assert_files_identical "flake.lock untouched" "$TMP/before.lock" "$FLAKE/flake.lock"
