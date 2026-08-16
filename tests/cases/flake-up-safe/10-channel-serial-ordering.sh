#!/usr/bin/env bash
# Property 10: the release bucket lists lexicographically, which is not
# chronological — nixos-26.05.889 sorts *after* nixos-26.05.7675. Ordering has
# to come from the serial in the name, which is a commit count and only goes up.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: channel releases order by serial, not lexically"

use_stubs nix git curl gh
sim_init
T=1767225600
BASE_REV="$(hexrev base)"
sim_input nixpkgs NixOS/nixpkgs nixos-26.05 "$BASE_REV" "$((T - 40 * 86400))" \
  "$(idxrev 0)" "$((T + 10 * 86400))"
sim_write

# Serial 889 sorts after 7675 as a string and before it as a number. The bucket
# lists them in the wrong order on purpose (sim_channel_releases sorts them
# lexicographically, exactly as S3 does).
sim_channel_releases nixos/26.05/ 26.05 . <<EOF
7675	$(idxrev 0)	$((T + 10 * 86400))
7000	$(idxrev 1)	$((T + 5 * 86400))
889	$(idxrev 2)	$((T + 1 * 86400))
100	$(idxrev 3)	$((T - 5 * 86400))
EOF

# Nothing builds but the baseline, so every candidate is visited in order.
sim_verdict <<EOF
grep -qx 'nixpkgs=$BASE_REV' && exit 0
exit 1
EOF

run_flake_up_safe -f "$FLAKE"

assert_exit "exits 0" 0
assert_eq "four candidates, the tip plus three older releases" \
  "nixpkgs: 4 candidate(s) from channel releases, newest first" \
  "$(grep -o 'nixpkgs: .*newest first' <<<"$STDOUT")"
assert_eq "probed newest-first by serial" "0 1 2 3" "$(probed_indices "$STDOUT")"
# Index 0 is labelled by date ("… (tip)"), so only the three older releases
# carry a name here — and they descend by serial rather than sorting 889 last.
assert_eq "the labels descend by serial" \
  "7000 889 100" \
  "$(grep -oE 'nixos-26\.05\.[0-9]+' <<<"$STDOUT" | sed 's/nixos-26\.05\.//' | tr '\n' ' ' | sed 's/ $//')"
