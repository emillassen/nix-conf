#!/usr/bin/env bash
# SIGTERM and SIGHUP restore the lock, and must also stop the nix that is
# running. On a terminal the trial's nix runs in the background while the
# script draws its elapsed-time line, and the trap used to exit with that child
# still building - consuming the machine after the run said it had stopped. Off
# a terminal the trap could not even run until the foreground build finished,
# which for a world rebuild is hours of ignoring the signal.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: a signal stops the build it interrupts"

use_stubs nix git curl gh
require_tool script flock

setup() {
  sim_init
  rm -f "$STUBLOG/builds.log" "$SIM/build-pid"
  T=1767225600
  BASE="$(hexrev base)" TIP="$(hexrev tip)"
  sim_input hm org/hm main "$BASE" "$((T - 10 * 86400))" "$TIP" "$T"
  sim_write
  # The baseline builds at once; the tip takes far longer than the case waits.
  sim_verdict <<EOF
grep -qx "hm=$TIP" && sleep 20
exit 0
EOF
  cp "$FLAKE/flake.lock" "$TMP/lock-before"
}

# Waits for the tip's build to be under way, sends SIG to the run, and reports
# whether the run stopped and whether the build's nix outlived it. The run is
# flake-up-safe.sh's own process, not the runner: on the terminal route the pty
# is kept open after it exits (closing it would hang the orphan up for us, which
# a real terminal that stays open does not do).
interrupt() {
  local sig="$1" runner="$2" i pid="" fus=""
  for i in $(seq 100); do
    if [[ -s "$SIM/build-pid" ]] && grep -q "hm=$TIP" "$STUBLOG/builds.log" 2>/dev/null; then
      pid="$(cat "$SIM/build-pid")"
      break
    fi
    sleep 0.1
  done
  [[ -n "$pid" ]] || {
    fail "harness: the tip's build never started"
    return
  }
  fus="$(pgrep -f -x "$HARNESS_BASH $FLAKE_UP_SAFE -f $FLAKE")"
  kill -"$sig" "$fus" 2>/dev/null
  for i in $(seq 50); do
    kill -0 "$fus" 2>/dev/null || break
    sleep 0.1
  done
  STOPPED_RUNNER=1
  kill -0 "$fus" 2>/dev/null && STOPPED_RUNNER=0
  BUILD_ALIVE=0
  kill -0 "$pid" 2>/dev/null && BUILD_ALIVE=1
  # Checked now, while the terminal route's pty is still open: closing it hangs
  # up whatever was left running, which would hide a child still holding the
  # run's lock on the checkout.
  LOCK_FREE=0
  "$REALBIN/flock" -n "$FLAKE" -c true 2>/dev/null && LOCK_FREE=1
  kill "$pid" 2>/dev/null
  kill "$runner" 2>/dev/null
  wait "$runner" 2>/dev/null
}

for route in terminal pipe; do
  for sig in TERM HUP; do
    setup
    if [[ "$route" == terminal ]]; then
      script -qec "env PATH='$(test_path)' '$HARNESS_BASH' '$FLAKE_UP_SAFE' -f '$FLAKE'; sleep 10" /dev/null \
        >"$TMP/out" 2>&1 &
    else
      env PATH="$(test_path)" "$HARNESS_BASH" "$FLAKE_UP_SAFE" -f "$FLAKE" >"$TMP/out" 2>&1 &
    fi
    interrupt "$sig" $!
    assert_eq "$route, SIG$sig: the run stops promptly" 1 "$STOPPED_RUNNER"
    assert_eq "$route, SIG$sig: and takes its build down with it" 0 "$BUILD_ALIVE"
    assert_eq "$route, SIG$sig: leaving nothing holding the checkout's lock" 1 "$LOCK_FREE"
    assert_files_identical "$route, SIG$sig: flake.lock is restored" \
      "$TMP/lock-before" "$FLAKE/flake.lock"
  done
done
