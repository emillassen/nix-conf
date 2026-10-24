#!/usr/bin/env bash
# A channel-tracking nixpkgs is bisected over the channel's own releases, because
# only those have passed Hydra: an arbitrary commit between two of them is a
# local rebuild of the world. When the release listing could not be fetched, the
# empty list used to read as "the tip is not a published release" and the run
# fell back to a per-day commit search - exactly the candidates the channel
# search exists to avoid, on nothing more than a network error.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: a release listing that cannot be fetched"

use_stubs nix git curl gh
sim_init
T=1767225600
BASE="$(hexrev base)" TIP="$(idxrev 0)"
sim_input nixpkgs NixOS/nixpkgs nixos-unstable "$BASE" "$((T - 10 * 86400))" "$TIP" "$T"
sim_write
printf 'https://nix-releases.s3.amazonaws.com/?prefix=*\t503\t-\n' >>"$CURL_MAP"
# Answers for every day, so a fallback would find something to build.
for d in 1 2 3; do
  sim_gh_day NixOS/nixpkgs "$(date -u -d "@$((T - d * 86400))" +%F)" "$(hexrev "day$d")"
done
sim_verdict <<EOF
grep -qx "nixpkgs=$TIP" && exit 1
exit 0
EOF

run_flake_up_safe -f "$FLAKE" -d 5

assert_exit "exits 0" 0
assert_eq "no commit was looked up" 0 "$(stub_count gh)"
assert_eq "nixpkgs stays at its baseline" "$BASE" "$(lock_rev nixpkgs)"
assert_contains "and the listing is blamed, not the input" "$STDOUT" \
  "could not list the nixos-unstable releases"
assert_not_contains "no verdict on revisions never built" "$STDOUT" \
  "No revision newer than the baseline builds"
