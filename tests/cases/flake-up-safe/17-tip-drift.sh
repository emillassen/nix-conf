#!/usr/bin/env bash
# `nix flake update` resolves a branch through nix's tarball-ttl cache (an hour
# by default). update_all refreshes past it; compose does not — so a run longer
# than an hour, which is the normal case here, can have a tip move under it and
# compose a later trial from a revision the run never recorded as "the tip".
#
# The recipe lock cache does not prevent it: each distinct recipe runs its own
# update, and the halves the partition tries are all distinct recipes.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: a tip that moves mid-run"

use_stubs nix git curl gh
sim_init
T=1767225600
for n in a b c d; do
  sim_input "$n" "org/$n" main "base-$n" "$((T - 30 * 86400))" "tip-$n" "$T"
done
sim_write

# An hour into the run the branch behind `a` moves. Only a non-refreshing
# update sees it, which is exactly what compose issues.
printf 'a\tdrifted-a\t%s\n' "$((T + 3600))" >"$SIM/tips-drift"
sim_rev drifted-a "$((T + 3600))"

sim_verdict <<'EOF'
grep -qx 'd=tip-d' && exit 1
exit 0
EOF

run_flake_up_safe -f "$FLAKE" --no-bisect

assert_exit "exits 0" 0
assert_eq "the written lock holds the tip the run started from" "tip-a" "$(lock_rev a)"
assert_eq "d is held back as expected" "base-d" "$(lock_rev d)"
# Every trial that said "a at its tip" tested the same revision.
assert_eq "no trial ever tested the drifted revision" 0 \
  "$(build_combos | grep -c 'a=drifted-a' || true)"
