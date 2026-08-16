#!/usr/bin/env bash
# Property 11b: the reason the linear prefix exists. A window that reads
# bad-good-bad-good from the tip backwards breaks the monotonicity the skipping
# search assumes, and a pure doubling search lands on the older good stretch.
#
# The window: the tip is broken, one day back builds (the true newest), days 2
# through 23 are broken again, and days 24 and older build. CLAUDE.md quotes
# measured numbers for exactly this shape; these are those numbers, re-measured.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: what the linear prefix buys"

use_stubs nix git curl gh
sim_init
T=1767225600
BASE_REV="$(hexrev base)"
sim_input hm org/hm main "$BASE_REV" "$((T - 90 * 86400))" "$(idxrev 0)" "$T"
sim_write
for i in $(seq 1 45); do
  sim_gh_day org/hm "$(date -u -d "@$((T - i * 86400))" +%F)" "$(idxrev "$i")" "$((T - i * 86400))"
done

# idxrev encodes the index in the first seven characters, so the truth table is
# a numeric test on the revision itself.
sim_verdict <<EOF
combo="\$(cat)"
grep -qx "hm=$BASE_REV" <<<"\$combo" && exit 0
rev="\$(sed -n 's/^hm=//p' <<<"\$combo")"
i=\$((10#\${rev:0:7}))
{ [ "\$i" -eq 1 ] || [ "\$i" -ge 24 ]; } && exit 0
exit 1
EOF

run_flake_up_safe -f "$FLAKE" -d 40 -l 7
assert_eq "the default finds the true newest" "$(idxrev 1)" "$(lock_rev hm)"
assert_eq "and pays three builds for it" 3 "$(builds_run)"
assert_eq "having probed only the tip and the day behind it" "0 1" "$(probed_indices "$STDOUT")"

# Same window, no linear prefix: the doubling walk steps straight over the good
# day next to the tip and settles in the older good stretch instead.
rm -f "$STUBLOG/builds.log" "$STUBLOG"/curl-n-*
cp "$SIM/head.lock" "$FLAKE/flake.lock"
run_flake_up_safe -f "$FLAKE" -d 40 -l 0
assert_eq "--linear 0 settles 23 days further back" "$(idxrev 24)" "$(lock_rev hm)"
assert_eq "for more than three times the builds" 10 "$(builds_run)"
assert_eq "the doubling walk, then the narrowing pass" \
  "0 2 6 14 30 22 26 24 23" "$(probed_indices "$STDOUT")"
