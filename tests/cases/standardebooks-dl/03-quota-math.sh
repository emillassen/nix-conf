#!/usr/bin/env bash
# The quota arithmetic, driven directly. These are the numbers that decide
# whether a fortnight-long sync stays inside standardebooks.org's limiter or
# spends the fortnight collecting 429s, and they are far too fiddly to check
# only through a whole run.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: quota arithmetic"

se_init
use_test_path

# The limiter's constants come out of the script itself, so a change there shows
# up here rather than being silently shadowed by a copy.
eval "$(grep -E '^(SHORT_WINDOW|SHORT_MAX|LONG_WINDOW|LONG_MAX|QUOTA_SLACK|MIN_INTERVAL)=[0-9]+' "$SEDL")"
assert_eq "the short window is the measured 30s" 30 "$SHORT_WINDOW"
assert_eq "the short limit is the measured 35" 35 "$SHORT_MAX"
assert_eq "the long window is six hours" 21600 "$LONG_WINDOW"
assert_eq "the long limit is the measured 100" 100 "$LONG_MAX"

quota_file="$TMP/quota"
extract_funcs "$SEDL" "$TMP/quota-funcs.sh" \
  quota_load quota_used quota_record quota_wait_for quota_wait fmt_duration
# shellcheck source=/dev/null
. "$TMP/quota-funcs.sh"

NOW=1800000000

# --- quota_load ------------------------------------------------------------------
: >"$quota_file"
stamps=(x)
quota_load "$NOW"
assert_eq "an empty ledger loads to nothing" 0 "${#stamps[@]}"

{
  echo "$((NOW - LONG_WINDOW - 1))" # aged out by one second
  echo ""
  echo "not-a-number"
  echo "$((NOW - LONG_WINDOW))" # exactly on the edge: still counts
  echo "$((NOW - 10))"
  echo "$((NOW + 120))" # a clock that went backwards, or a shared ledger
} >"$quota_file"
stamps=()
quota_load "$NOW"
assert_eq "junk, blanks and aged-out entries are dropped" 3 "${#stamps[@]}"
assert_eq "the boundary entry is kept" "$((NOW - LONG_WINDOW))" "${stamps[0]}"
assert_eq "a future timestamp is kept rather than treated as spent" \
  "$((NOW + 120))" "${stamps[2]}"
assert_eq "and the pruned list is written back" 3 "$(grep -c '' "$quota_file")"
assert_not_contains "with the junk gone for good" "$(cat "$quota_file")" "not-a-number"

# --- quota_wait_for: the short window ---------------------------------------------
# The comparison is strictly greater, so exactly SHORT_MAX in the window is
# still allowed through — that is what the live probing found, request 37 of an
# unpaced burst being the first 429.
recent=()
for i in $(seq 1 "$SHORT_MAX"); do recent+=("$((NOW - 20 + i))"); done
assert_eq "exactly 35 in 30s asks for no wait" "" "$(quota_wait_for recent "$SHORT_MAX" "$SHORT_WINDOW" "$NOW")"

recent=("$((NOW - 25))")
for i in $(seq 1 "$SHORT_MAX"); do recent+=("$((NOW - 20 + i))"); done
# 36 entries: the oldest has to age out, so wait until it is SHORT_WINDOW old
# plus the slack that keeps us off the boundary.
assert_eq "36 waits for the oldest to age out" \
  "$((NOW - 25 + SHORT_WINDOW + QUOTA_SLACK - NOW))" \
  "$(quota_wait_for recent "$SHORT_MAX" "$SHORT_WINDOW" "$NOW")"

# --- quota_wait_for: the long window ----------------------------------------------
long=()
for i in $(seq 1 "$LONG_MAX"); do long+=("$((NOW - LONG_WINDOW + i))"); done
assert_eq "exactly 100 in six hours asks for no wait" "" \
  "$(quota_wait_for long "$LONG_MAX" "$LONG_WINDOW" "$NOW")"

long=("$((NOW - LONG_WINDOW + 100))" "${long[@]}")
assert_eq "101 waits on the oldest of them" \
  "$((NOW - LONG_WINDOW + 100 + LONG_WINDOW + QUOTA_SLACK - NOW))" \
  "$(quota_wait_for long "$LONG_MAX" "$LONG_WINDOW" "$NOW")"

# Three over the limit waits on the third-oldest, not the first.
long=()
for i in 1 2 3; do long+=("$((NOW - LONG_WINDOW + i * 10))"); done
for i in $(seq 1 "$LONG_MAX"); do long+=("$((NOW - 100 + i))"); done
assert_eq "103 waits on the third-oldest" \
  "$((NOW - LONG_WINDOW + 30 + LONG_WINDOW + QUOTA_SLACK - NOW))" \
  "$(quota_wait_for long "$LONG_MAX" "$LONG_WINDOW" "$NOW")"

# --- fmt_duration -----------------------------------------------------------------
assert_eq "seconds" "45s" "$(fmt_duration 45)"
assert_eq "minutes" "5m" "$(fmt_duration 300)"
assert_eq "hours" "6h00m" "$(fmt_duration 21600)"
assert_eq "days" "14d18h" "$(fmt_duration $((14 * 86400 + 18 * 3600)))"
