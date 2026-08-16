#!/usr/bin/env bash
# The release bucket holds a decade of releases under nixos/unstable/, so the
# listing starts at a marker rather than at the beginning. That marker is a
# guess, and a wrong guess is not loud: the tip simply is not in the list and
# the run drops back to a per-day commit search of a branch whose commits Hydra
# never built — the exact thing channel releases exist to avoid.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: the S3 listing marker"

use_stubs nix git curl gh

# --- A stable channel older than a calendar year -------------------------------
# nixos-25.05 releases are still named nixos-25.05.NNNN in 2027, and they all
# sort before a marker guessed from the tip's year.
sim_init
T=1804204800 # 2027-03-01
BASE_REV="$(hexrev base)"
sim_input nixpkgs NixOS/nixpkgs nixos-25.05 "$BASE_REV" "$((T - 40 * 86400))" \
  "$(idxrev 0)" "$T"
sim_write
sim_channel_releases nixos/25.05/ 25.05 . <<EOF
9000	$(idxrev 0)	$T
8000	$(idxrev 1)	$((T - 5 * 86400))
EOF
sim_verdict <<EOF
grep -qx "nixpkgs=$BASE_REV" && exit 0
exit 1
EOF

run_flake_up_safe -f "$FLAKE"
assert_contains "an old stable channel still lists its releases" "$STDOUT" \
  "candidate(s) from channel releases"
assert_not_contains "and does not fall back to commits" "$STDOUT" \
  "falling back to commits"

# --- Unstable across a year boundary -------------------------------------------
# On 2 January 2026 the rolling channel is still publishing nixos-25.11pre…,
# so the year-based guess has to reach back past the turn of the year.
rm -f "$STUBLOG/builds.log"
sim_init
T2=1767312000 # 2026-01-02
sim_input nixpkgs NixOS/nixpkgs nixos-unstable "$BASE_REV" "$((T2 - 40 * 86400))" \
  "$(idxrev 0)" "$T2"
sim_write
sim_channel_releases nixos/unstable/ 25.11 pre <<EOF
861234	$(idxrev 0)	$T2
861000	$(idxrev 1)	$((T2 - 2 * 86400))
EOF
sim_verdict <<EOF
grep -qx "nixpkgs=$BASE_REV" && exit 0
exit 1
EOF

run_flake_up_safe -f "$FLAKE"
assert_contains "unstable's list survives the turn of the year" "$STDOUT" \
  "2 candidate(s) from channel releases"
