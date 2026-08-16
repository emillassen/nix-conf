#!/usr/bin/env bash
# fetch_url's answer to a 429. A refused request is never recorded by the site,
# so being blocked cannot deepen the hole and nothing can stay blocked longer
# than the six-hour window — which makes outlasting it the correct escape hatch
# rather than giving up after a few tries and marking good books failed.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: fetch_url backoff"

se_init
use_test_path
eval "$(grep -E '^(LONG_WINDOW)=[0-9]+' "$SEDL")"
ua="test"
warnings=()
extract_funcs "$SEDL" "$TMP/fetch.sh" warn fmt_duration fetch_url
# shellcheck source=/dev/null
. "$TMP/fetch.sh"

# --- a 429 that clears ---------------------------------------------------------
{
  printf 'https://x/blocked\t429\t-\n'
  printf 'https://x/blocked\t429\t-\n'
  printf 'https://x/blocked\t200\tthe book\n'
} >>"$CURL_MAP"
rc=0
out="$(fetch_url https://x/blocked "$TMP/got" 2>&1)" || rc=$?
assert_eq "it comes back with the file" 0 "$rc"
assert_eq "after doubling twice" "60 120" "$(stub_log sleep | tr '\n' ' ' | sed 's/ $//')"
assert_contains "and says why it waited" "$out" "the ledger is behind the server"
assert_file_contains "the body landed" "$TMP/got" "the book"

# --- a 429 that never clears ----------------------------------------------------
rm -f "$STUBLOG/sleep.log" "$STUBLOG"/curl-n-*
: >"$CURL_MAP"
printf 'https://x/wall\t429\t-\n' >>"$CURL_MAP"
rc=0
out="$(fetch_url https://x/wall "$TMP/got2" 2>&1)" || rc=$?
assert_eq "it eventually gives up" 1 "$rc"
assert_eq "having doubled and then capped at 900" "60 120 240 480 900 900" \
  "$(stub_log sleep | head -n 6 | tr '\n' ' ' | sed 's/ $//')"
assert_eq "the cap is never exceeded" 900 "$(sort -n "$STUBLOG/sleep.log" | tail -n1)"
total="$(awk '{ n += $1 } END { print n }' "$STUBLOG/sleep.log")"
assert_eq "and it outlasts the six-hour window plus half an hour" \
  "$((LONG_WINDOW + 1800))" "$total"
assert_contains "then says so" "$out" "still rate-limited after 6h30m"

# --- a 404 ----------------------------------------------------------------------
rm -f "$STUBLOG/sleep.log"
: >"$CURL_MAP"
printf 'https://x/gone\t404\t-\n' >>"$CURL_MAP"
rc=0
fetch_url https://x/gone "$TMP/got3" || rc=$?
assert_eq "a 404 is its own answer, not a failure" 2 "$rc"
assert_eq "and costs no waiting" 0 "$(stub_count sleep)"

# --- a 5xx ------------------------------------------------------------------------
# The site being down is not a verdict on this book. Without a retry a
# maintenance window turns every remaining book in a fortnight-long run into a
# failure, a few paced seconds apart.
rm -f "$STUBLOG/sleep.log" "$STUBLOG"/curl-n-*
: >"$CURL_MAP"
{
  printf 'https://x/down\t503\t-\n'
  printf 'https://x/down\t503\t-\n'
  printf 'https://x/down\t200\tback up\n'
} >>"$CURL_MAP"
rc=0
fetch_url https://x/down "$TMP/got4" 2>/dev/null || rc=$?
assert_eq "a 5xx is waited out too" 0 "$rc"
assert_file_contains "and the file arrives" "$TMP/got4" "back up"

rm -f "$STUBLOG/sleep.log" "$STUBLOG"/curl-n-*
: >"$CURL_MAP"
printf 'https://x/dead\t500\t-\n' >>"$CURL_MAP"
rc=0
fetch_url https://x/dead "$TMP/got5" 2>/dev/null || rc=$?
assert_eq "but not forever" 1 "$rc"
assert_eq "on a small fixed budget, unlike a 429" "60 120 180" \
  "$(stub_log sleep | tr '\n' ' ' | sed 's/ $//')"
