#!/usr/bin/env bash
# Property 3: a breakage that only exists in combination. `a` alone builds, `b`
# alone builds, `a`+`b` together do not. CLAUDE.md claims the partition scheme
# catches this without a separate combine pass, because every trial is
# "everything kept so far, plus this half". Prove it.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: breakage only in combination"

use_stubs nix git curl gh
sim_init
sim_input a org/a main base-a 1750000000 tip-a 1755000000
sim_input b org/b main base-b 1750000000 tip-b 1755000000
sim_input c org/c main base-c 1750000000 tip-c 1755000000
sim_input d org/d main base-d 1750000000 tip-d 1755000000
sim_write
sim_verdict <<'EOF'
combo="$(cat)"
if grep -q '^a=tip-a$' <<<"$combo" && grep -q '^b=tip-b$' <<<"$combo"; then
  echo "error: a and b together do not build" >&2
  exit 1
fi
exit 0
EOF

run_flake_up_safe -f "$FLAKE" --no-bisect

assert_exit "exits 0" 0
# The pair is genuinely incompatible, so exactly one of them has to stay back;
# which one is an artefact of the partition order (a is absorbed first).
assert_eq "a took its tip" "tip-a" "$(lock_rev a)"
assert_eq "b was held back" "base-b" "$(lock_rev b)"
assert_eq "c reached its tip" "tip-c" "$(lock_rev c)"
assert_eq "d reached its tip" "tip-d" "$(lock_rev d)"

# The written lock must never be one the verdict rejects: that is the whole
# point of the final whole-combination trial.
assert_not_contains "no build of the broken pair was accepted" "$STDOUT" \
  "does not build together"
final_combo="$(build_combos | tail -n1)"
assert_not_contains "the last build was not the broken pair" "$final_combo" "b=tip-b"
