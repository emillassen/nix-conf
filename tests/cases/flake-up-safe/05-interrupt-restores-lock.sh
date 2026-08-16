#!/usr/bin/env bash
# Property 5: a Ctrl-C mid-trial exits 130 and leaves flake.lock exactly as
# found — a run that dies halfway must never leave a half-searched lock behind.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: interrupt restores the lock"

use_stubs nix git curl gh
sim_init
sim_input a org/a main base-a 1750000000 tip-a 1755000000
sim_input b org/b main base-b 1750000000 tip-b 1755000000
sim_write
cp "$FLAKE/flake.lock" "$TMP/before.lock"

# The baseline builds; the very next trial is interrupted. 130 is what a nix
# killed by SIGINT exits with, and it is what abort_if_interrupted keys on.
sim_verdict <<'EOF'
n="$FLAKE_SIM/verdict-count"
c=0; [ -f "$n" ] && c=$(cat "$n")
echo $((c + 1)) >"$n"
if [ "$c" -ge 1 ]; then
  echo "error: interrupted by the user" >&2
  exit 130
fi
exit 0
EOF

run_flake_up_safe -f "$FLAKE"

assert_exit "exits 130" 130
assert_contains "says it was interrupted" "$STDERR" "interrupted."
assert_files_identical "flake.lock untouched" "$TMP/before.lock" "$FLAKE/flake.lock"
assert_contains "keeps the logs for inspection" "$STDERR" "logs kept in"
