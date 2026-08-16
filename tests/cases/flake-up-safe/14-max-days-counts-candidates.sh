#!/usr/bin/env bash
# --max-days caps the *candidate list length*, not a span of days. For a
# channel-tracking nixpkgs a candidate is a release and unstable publishes
# several a day, so -d 3 reaches nowhere near three days back. This pins the
# behaviour; the help text and CLAUDE.md are what had to change.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: --max-days counts candidates"

use_stubs nix git curl gh
sim_init
T=1767225600
BASE_REV="$(hexrev base)"
sim_input nixpkgs NixOS/nixpkgs nixos-unstable "$BASE_REV" "$((T - 90 * 86400))" \
  "$(idxrev 0)" "$T"
sim_write

# Five releases, all published within a single day of each other.
sim_channel_releases nixos/unstable/ 26.05 pre <<EOF
9004	$(idxrev 0)	$T
9003	$(idxrev 1)	$((T - 3600))
9002	$(idxrev 2)	$((T - 7200))
9001	$(idxrev 3)	$((T - 10800))
9000	$(idxrev 4)	$((T - 14400))
EOF
sim_verdict <<EOF
grep -qx "nixpkgs=$BASE_REV" && exit 0
exit 1
EOF

run_flake_up_safe -f "$FLAKE" -d 3
assert_contains "three candidates, spanning three hours" "$STDOUT" \
  "nixpkgs: 3 candidate(s) from channel releases"
assert_eq "and it probed exactly those three" "0 1 2" "$(probed_indices "$STDOUT")"
