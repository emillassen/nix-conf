#!/usr/bin/env bash
# Property 7: a bisect that lands on something no newer than the baseline must
# write no pin. The interesting case is a channel list, which runs *past* the
# baseline whenever the baseline is not itself a published release — so the test
# has to be on lastModified, not on revision equality.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: bisect finds nothing newer than the baseline"

use_stubs nix git curl gh
sim_init

T=1767225600 # 2026-01-01
BASE_REV="$(hexrev base)"
sim_input nixpkgs NixOS/nixpkgs nixos-unstable "$BASE_REV" "$T" "$(idxrev 0)" "$((T + 10 * 86400))"
sim_write

# Four published releases, the newest of which is the tip. The baseline is not
# among them (it is an ordinary commit), so the list has nothing to stop at and
# runs off the far end into revisions older than the baseline.
sim_channel_releases nixos/unstable/ 26.05 pre <<EOF
9000	$(idxrev 0)	$((T + 10 * 86400))
8000	$(idxrev 1)	$((T + 5 * 86400))
7000	$(idxrev 2)	$((T + 1 * 86400))
6000	$(idxrev 3)	$((T - 2 * 86400))
EOF

# Only the release *older* than the baseline builds.
sim_verdict <<EOF
combo="\$(cat)"
grep -qx 'nixpkgs=$(idxrev 3)' <<<"\$combo" && exit 0
grep -qx 'nixpkgs=$BASE_REV' <<<"\$combo" && exit 0
exit 1
EOF

run_flake_up_safe -f "$FLAKE"

assert_exit "exits 0" 0
assert_contains "candidates came from the channel" "$STDOUT" "candidate(s) from channel releases"
assert_contains "refuses to pin something older" "$STDOUT" \
  "nothing newer than the baseline builds; staying at baseline"
assert_eq "the input stays at its baseline revision" "$BASE_REV" "$(lock_rev nixpkgs)"
assert_not_contains "no pin is reported" "$STDOUT" "bisected"
assert_contains "the lock is left as it was" "$STDOUT" \
  "Nothing improved on the baseline; flake.lock unchanged."

# Index 0 of the candidate list is the tip, which the partition already
# rejected: re-composing it hits the .drv cache and costs nothing.
assert_contains "re-testing the tip was free" "$STDOUT" "identical to t02"
assert_eq "five builds" 5 "$(builds_run)"
