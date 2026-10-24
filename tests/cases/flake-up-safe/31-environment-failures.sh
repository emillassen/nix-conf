#!/usr/bin/env bash
# Failures of the environment rather than of the inputs. Each of these used to
# be recorded as an ordinary verdict on whatever was being tried, so the run
# went on to blame inputs, or carried on from a state it had not composed:
#
#   - host discovery ran `nix eval` before the original lock was backed up, so
#     an eval that rewrote flake.lock made that the lock "restored" at the end;
#   - a second run against the same checkout shared its flake.lock unguarded;
#   - a lock-cache copy that failed was reported as a composed lock;
#   - a `-k` check that died of a full disk was a failed check, not a dead run;
#   - an evaluation that hit a network blip got no retry, unlike a build.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: environment failures"

use_stubs nix git curl gh
require_tool flock

setup() {
  sim_init
  rm -f "$STUBLOG/builds.log"
  T=1767225600
  BASE="$(hexrev base)" TIP="$(hexrev tip)"
  sim_input hm org/hm main "$BASE" "$((T - 10 * 86400))" "$TIP" "$T"
  sim_write
  sim_verdict <<'EOF'
exit 0
EOF
  cp "$FLAKE/flake.lock" "$TMP/lock-before"
}

# --- host discovery may not write the lock ------------------------------------------
setup
: >"$SIM/eval-writes-lock"
run_flake_up_safe -f "$FLAKE" -n
assert_exit "-n with a lock-writing eval: exits 0" 0
assert_files_identical "flake.lock is exactly as it was" "$TMP/lock-before" "$FLAKE/flake.lock"
rm -f "$SIM/eval-writes-lock"

# --- one run per checkout ------------------------------------------------------------
setup
# One process holding it, exec'd into sleep, so killing it lets go: flock -c
# would leave its sleep child holding the lock after flock itself was killed.
(
  exec 9<"$FLAKE"
  "$REALBIN/flock" 9
  exec sleep 30
) &
holder=$!
for _ in $(seq 50); do
  "$REALBIN/flock" -n "$FLAKE" -c true 2>/dev/null || break
  sleep 0.1
done
run_flake_up_safe -f "$FLAKE" -n
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null
assert_ne "a second run on the same flake is refused" 0 "$STATUS"
assert_contains "and says why" "$STDERR" "another flake-up-safe is already running"
assert_files_identical "leaving flake.lock alone" "$TMP/lock-before" "$FLAKE/flake.lock"

# --- a lock that cannot be put in place is the end of the run ---------------------
# The all-at-tips lock is handed to the cache before the first trial, so the
# first trial is a cache hit - and a cp that fails there left the baseline on
# disk, built it, and accepted every tip on the strength of it.
setup
real_cp="$(PATH="$HOST_PATH" command -v cp)"
cat >"$STUBDIR/cp" <<EOF
#!$HARNESS_BASH
args=("\$@")
[[ "\${args[0]}" == -- ]] && args=("\${args[@]:1}")
[[ "\${args[0]}" == */locks/*.lock && "\${args[1]}" == */flake.lock ]] && { echo "cp: write error" >&2; exit 1; }
exec "$real_cp" "\$@"
EOF
chmod +x "$STUBDIR/cp"
run_flake_up_safe -f "$FLAKE"
rm -f "$STUBDIR/cp"
assert_ne "a failed lock copy fails the run" 0 "$STATUS"
assert_not_contains "rather than writing a verified lock" "$STDOUT" "Wrote flake.lock (verified)"
assert_files_identical "and flake.lock is restored" "$TMP/lock-before" "$FLAKE/flake.lock"

# --- a full disk during -k is the environment, not the lock ------------------------
setup
sim_check <<EOF
combo="\$(cat)"
grep -qx "hm=$TIP" <<<"\$combo" || exit 0
echo "error: writing to file: No space left on device" >&2
exit 1
EOF
run_flake_up_safe -f "$FLAKE" -k
assert_ne "a full disk in flake check ends the run" 0 "$STATUS"
assert_contains "as an environment failure" "$STDERR" "the build environment failed"
rm -f "$SIM/check.sh"

# --- an evaluation that hits a network blip is retried -----------------------------
setup
cat >"$SIM/eval.sh" <<EOF
#!$HARNESS_BASH
if [[ ! -e "$SIM/eval-blipped" ]] && grep -qx "hm=$TIP"; then
  : >"$SIM/eval-blipped"
  echo "error: unable to download 'https://github.com/org/hm/archive/x.tar.gz': HTTP error 503" >&2
  exit 1
fi
exit 0
EOF
chmod +x "$SIM/eval.sh"
run_flake_up_safe -f "$FLAKE"
assert_exit "a transient evaluation failure: exits 0" 0
assert_contains "it is retried" "$STDOUT" "network trouble evaluating, retrying once"
assert_eq "and the tip is taken" "$TIP" "$(lock_rev hm)"
rm -f "$SIM/eval.sh"
