#!/usr/bin/env bash
# The bucket serves at most 1000 keys per request and says so with
# <IsTruncated>true</IsTruncated>; s3_releases is supposed to follow that with a
# marker until the listing runs out. Nothing had ever exercised it, because the
# stub could not express a truncated page at all.
#
# It matters for the same reason the marker does (case 19): if the tip is not
# found in the list, the run says "tip is not a published release" and quietly
# drops to a per-day commit search — revisions Hydra never built, i.e. a local
# rebuild of the world. A marker set a year back plus a channel publishing
# several releases a day is enough to push the tip onto the second page.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: a channel listing that spans two pages"

use_stubs nix git curl gh

# Readable 40-hex revisions: the first seven characters are the short rev a
# release name carries, so the probe lines say which release was tried.
rev40() { printf '%s%0*d' "$1" "$((40 - ${#1}))" 0; }

sim_init
T=1755000000 # 2025-08-12
TIP="$(rev40 c0ffee3)"
ONE="$(rev40 d00d111)"
TWO="$(rev40 d00d222)"
BASE="$(rev40 badbeef)"
sim_input nixpkgs NixOS/nixpkgs nixos-unstable "$BASE" "$((T - 10 * 86400))" "$TIP" "$T"
sim_write

sim_channel_releases nixos/unstable/ 26.05 pre <<EOF
900003	$TIP	$T
900002	$ONE	$((T - 86400))
900001	$TWO	$((T - 2 * 86400))
900000	$BASE	$((T - 10 * 86400))
EOF
# Exactly one page of older keys ahead of them, so the four real releases are
# only reachable by following IsTruncated with a marker.
sim_channel_filler nixos/unstable/ 1000

# The tip is broken; the release a day behind it is fine.
sim_verdict <<EOF
grep -qx "nixpkgs=$TIP" && exit 1
exit 0
EOF

run_flake_up_safe -f "$FLAKE"
assert_exit "exits 0" 0
assert_contains "the tip is found despite being on the second page" "$STDOUT" \
  "3 candidate(s) from channel releases"
assert_not_contains "so the run does not drop to a commit search" "$STDOUT" \
  "falling back to commits"
assert_eq "the bucket was asked twice" 2 "$(stub_count curl-urls 'nix-releases.s3')"
assert_contains "the second request carried a marker from the first page" \
  "$(stub_log curl-urls)" "&marker=nixos/unstable/nixos-25.05pre001000.0000001/"

# And the search then does its ordinary job on the list it assembled.
assert_eq "the bisect settled on the release below the tip" "$ONE" "$(lock_rev nixpkgs)"
assert_contains "reported by release name" "$STDOUT" \
  "newest working candidate: nixos-26.05pre900002.d00d111"

# The padding is older than the baseline, which ends the list — a thousand keys
# in the bucket must not become a thousand candidates.
assert_not_contains "the filler never became a candidate" "$STDOUT" "nixos-25.05pre"
