#!/usr/bin/env bash
# quota_wait, driven against a fake clock: it must sleep exactly as long as the
# ledger says and no longer, announce a wait that is long enough to look like a
# hang, and stay quiet for routine spacing.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: quota_wait"

se_init
use_test_path
eval "$(grep -E '^(SHORT_WINDOW|SHORT_MAX|LONG_WINDOW|LONG_MAX|QUOTA_SLACK|MIN_INTERVAL)=[0-9]+' "$SEDL")"

quota_file="$TMP/quota"
quota_lock="$TMP/quota.lock"
quota_lock_held=0
extract_funcs "$SEDL" "$TMP/quota-funcs.sh" \
  quota_lock_hold quota_lock_free quota_load quota_used quota_record \
  quota_wait_for quota_wait fmt_duration
# shellcheck source=/dev/null
. "$TMP/quota-funcs.sh"

NOW=1800000000
set_now "$NOW"

# --- nothing spent -----------------------------------------------------------------
: >"$quota_file"
quota_wait
assert_eq "an empty ledger waits for nothing" 0 "$(stub_count sleep)"

# --- the MIN_INTERVAL floor ---------------------------------------------------------
# The quota is the real constraint; this only stops a whole window's budget
# going in a ninety-second burst.
printf '%s\n' "$((NOW - 5))" >"$quota_file"
rm -f "$STUBLOG/sleep.log"
quota_wait
assert_eq "one sleep to reach the floor" 1 "$(stub_count sleep)"
assert_eq "of exactly the remaining interval" "$((MIN_INTERVAL - 5))" "$(stub_log sleep | tr -d '\n')"
assert_eq "and the clock has moved on by it" "$((NOW + MIN_INTERVAL - 5))" "$(now)"

# --- the six-hour window spent --------------------------------------------------
# 101 downloads inside the window: the oldest has to age out before the next one
# is allowed, and a wait of hours has to say so or the run looks hung.
set_now "$NOW"
: >"$quota_file"
oldest=$((NOW - LONG_WINDOW + 3600))
printf '%s\n' "$oldest" >>"$quota_file"
for i in $(seq 1 "$LONG_MAX"); do printf '%s\n' "$((NOW - 200 + i))" >>"$quota_file"; done
rm -f "$STUBLOG/sleep.log"
out="$(quota_wait 2>&1)"
assert_contains "the long wait is announced" "$out" "download quota spent (101 in the last 6h)"
assert_contains "with a human duration" "$out" "resuming in 1h00m"
assert_eq "announced once, not once per loop" 1 \
  "$(grep -c 'download quota spent' <<<"$out")"
assert_eq "and it waited exactly until the oldest aged out" \
  "$((oldest + LONG_WINDOW + QUOTA_SLACK))" "$(now)"
