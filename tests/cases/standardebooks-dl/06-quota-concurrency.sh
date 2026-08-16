#!/usr/bin/env bash
# Two runs share the quota ledger by design — the cap is per IP address, so the
# help says outright that "two libraries synced from here draw on one budget".
# quota_load prunes by rewriting the whole file, though, so without a lock a
# rewrite that started before another run's append lands drops that append: both
# runs then believe they have budget they have already spent, and the site
# answers 429.
#
# The ledger here is far bigger than a real one (pruning keeps a real one near
# LONG_MAX) purely to widen the window between the read and the write until the
# race is reproducible on demand rather than once in a hundred runs.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: concurrent quota records"

se_init
require_tool flock
use_test_path
eval "$(grep -E '^(LONG_WINDOW)=[0-9]+' "$SEDL")"

quota_dir="$TMP/qdir"
mkdir -p "$quota_dir"
quota_file="$quota_dir/download-quota"
quota_lock="$quota_dir/lock"
quota_lock_held=0
extract_funcs "$SEDL" "$TMP/quota-funcs.sh" \
  quota_lock_hold quota_lock_free quota_load quota_used quota_record
# shellcheck source=/dev/null
. "$TMP/quota-funcs.sh"

NOW=1800000000
set_now "$NOW"
BASELINE=3000
: >"$quota_file"
for i in $(seq 1 "$BASELINE"); do printf '%s\n' "$((NOW - 1000 + i % 500))" >>"$quota_file"; done

# A start gate, so the workers genuinely overlap instead of being serialised by
# the cost of forking them one after another. Without the lock this loses
# records in most runs; with it, never.
WORKERS=10
gate="$TMP/gate"
for w in $(seq 1 "$WORKERS"); do
  (
    while [[ ! -e "$gate" ]]; do :; done
    # shellcheck source=/dev/null
    . "$TMP/quota-funcs.sh"
    quota_lock_held=0
    stamps=()
    quota_load "$NOW"
    quota_record
  ) &
done
sleep 0.3
touch "$gate"
wait

got="$(grep -c '' "$quota_file")"
assert_eq "every concurrent record survives" "$((BASELINE + WORKERS))" "$got"

# And the lock is not held past the call: a second load right after must not
# block. (If it did, this case would hang rather than fail, so the assertion is
# really the fact that we get here at all.)
stamps=()
quota_load "$NOW"
assert_eq "the ledger reads back complete" "$((BASELINE + WORKERS))" "${#stamps[@]}"

# The stress above only fails when the interleaving happens to be unlucky, so
# the mechanism itself gets a deterministic test too: hold the lock, and a
# second process must not be able to record until it is let go. The child
# reopens the lock file rather than inheriting the descriptor, which is what
# makes its flock a genuine second contender.
: >"$quota_file"
quota_lock_hold
(
  # shellcheck source=/dev/null
  . "$TMP/quota-funcs.sh"
  quota_lock_held=0
  quota_record
) &
blocked_pid=$!
sleep 0.4
assert_eq "a second run cannot record while the ledger is locked" 0 \
  "$(grep -c '' "$quota_file")"
quota_lock_free
wait "$blocked_pid"
assert_eq "and records the moment the lock is released" 1 "$(grep -c '' "$quota_file")"
