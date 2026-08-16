#!/usr/bin/env bash
# run_nix has three routes and the suite only ever took one of them. Every case
# redirects stdout to a file, so `[ -t 1 ]` is false and TTY is 0 — which means
# the background-pid/poll/`wait` route and -v's `tee` pipeline had never run at
# all, and both decide the exit status of every trial by their own means.
#
# The pipeline one is the sharper risk: `nix ... | tee` reports tee's status, so
# without pipefail a failing build under -v would be recorded as a success and
# a broken input would be written into flake.lock as verified.
#
# `script` supplies the pty. It merges stderr into the pty as well, so for those
# runs the whole session arrives in STDOUT and STDERR is empty.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: the terminal and -v output routes"

use_stubs nix git curl gh
require_tool script
sim_init
sim_input a org/a main base-a 1750000000 tip-a 1755000000
sim_input b org/b main base-b 1750000000 tip-b 1755000000
sim_write
cp "$FLAKE/flake.lock" "$TMP/before.lock"

# Same invocation as run_flake_up_safe, but with a pty on stdout so the progress
# route is the one taken.
run_on_tty() {
  local cmd
  cmd="$(printf '%q ' env PATH="$(test_path)" "$HARNESS_BASH" "$FLAKE_UP_SAFE" "$@")"
  _capture "$REALBIN/script" -qec "$cmd" /dev/null
}

# --- the terminal route ------------------------------------------------------
sim_verdict <<'EOF'
cat >/dev/null
exit 0
EOF

run_on_tty -f "$FLAKE"
assert_exit "a successful run exits 0 through the wait" 0
assert_eq "a reached its tip" "tip-a" "$(lock_rev a)"
assert_eq "b reached its tip" "tip-b" "$(lock_rev b)"

# A build that fails has to come back as a failure through the same `wait`, or
# the whole search silently accepts everything.
cp "$TMP/before.lock" "$FLAKE/flake.lock"
sim_verdict <<'EOF'
combo="$(cat)"
grep -qx 'b=tip-b' <<<"$combo" && exit 1
exit 0
EOF

run_on_tty -f "$FLAKE" --no-bisect
assert_exit "exits 0" 0
assert_eq "a reached its tip" "tip-a" "$(lock_rev a)"
assert_eq "the failing input is held back, not accepted" "base-b" "$(lock_rev b)"

# A trial slow enough to be worth a progress line gets one, and erases it after.
# The poll stays quiet for the first three seconds because most trials are
# answered from the .drv cache and a line that appears and vanishes is flicker.
cp "$TMP/before.lock" "$FLAKE/flake.lock"
# Only the one trial that moves a forward is slow; the baseline stays cheap, so
# the whole case pays the three-second threshold once rather than twice.
sim_verdict <<'EOF'
combo="$(cat)"
grep -qx 'a=tip-a' <<<"$combo" && sleep 3.5
exit 0
EOF

run_on_tty -f "$FLAKE" -i a
assert_exit "the slow run finishes" 0
assert_contains "the elapsed-time line appears" "$STDOUT" "· 0m0"
assert_contains "and is erased afterwards" "$STDOUT" $'\r\033[K'

# --- -v: nix gets the output, the log gets a copy -----------------------------
# -v turns the progress line off even on a terminal, and streams nix's own
# stderr instead. The status of the pipeline still has to be the build's.
cp "$TMP/before.lock" "$FLAKE/flake.lock"
sim_verdict <<'EOF'
combo="$(cat)"
if grep -qx 'b=tip-b' <<<"$combo"; then
  echo "error: builder for '/nix/store/x.drv' failed with exit code 1" >&2
  exit 1
fi
exit 0
EOF

run_flake_up_safe -f "$FLAKE" -v --no-bisect
assert_exit "exits 0" 0
assert_contains "nix's own output is streamed" "$STDERR" \
  "error: builder for '/nix/store/x.drv' failed with exit code 1"
assert_eq "a reached its tip" "tip-a" "$(lock_rev a)"
assert_eq "the tee pipeline did not swallow the failure" "base-b" "$(lock_rev b)"
assert_not_contains "and no progress line was printed" "$STDOUT" "·"

# The log the pipeline tees into is what report_error reads back, so the one
# line worth reading has to have landed there by the time it is read.
assert_contains "the failure is quoted back in the summary" "$STDOUT" \
  "error: builder for '/nix/store/x.drv' failed with exit code 1"
