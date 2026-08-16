#!/usr/bin/env bash
# Property 2: one culprit among eleven inputs. Every other input must reach its
# tip, and the binary partition must cost the documented "about seven trials
# instead of eleven".
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: one culprit among eleven"

use_stubs nix git curl gh
sim_init
for i in 01 02 03 04 05 06 07 08 09 10 11; do
  sim_input "i$i" "org/r$i" main "base$i" 1750000000 "tip$i" 1755000000
done
sim_write
sim_verdict <<'EOF'
grep -q '^i06=tip06$' && exit 1
exit 0
EOF

# --no-bisect keeps this case about the partition alone; the history search gets
# its own cases.
run_flake_up_safe -f "$FLAKE" --no-bisect

assert_exit "exits 0" 0
assert_eq "the culprit stays at its baseline" "base06" "$(lock_rev i06)"
for i in 01 02 03 04 05 07 08 09 10 11; do
  assert_eq "i$i reached its tip" "tip$i" "$(lock_rev "i$i")"
done
assert_contains "says which input is held back" "$STDOUT" "held back  i06"

# Seven partition trials, exactly as documented. One of them ("keeping 5,
# trying: i06…i11") recomposes the all-tips lock the first trial already
# rejected, so the .drv cache answers it and it costs no build: baseline + 6.
assert_eq "seven partition trials" 7 "$(grep -c -e '^  all 11' -e '^  keeping ' <<<"$STDOUT")"
assert_eq "seven builds, not twelve" 7 "$(builds_run)"
assert_contains "a repeated combination cost no build" "$STDOUT" \
  "✗ failed (identical to t02)"
