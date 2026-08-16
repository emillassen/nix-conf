#!/usr/bin/env bash
# yt-dlp's DRTV extractor only matches the canonical slug URLs
# (/drtv/serie/gurli-gris_7190). A bare-ID URL redirects there in a browser, so
# it is resolved the same way first — by the redirect if there is one, and by
# the page's rel="canonical" link if the server answers 200 with the SPA
# instead.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: resolving bare-ID URLs"

drtv_init
canon="https://www.dr.dk/drtv/serie/gurli-gris_7190"
bare="https://www.dr.dk/drtv/serie/7190"
season="https://www.dr.dk/drtv/saeson/gurli-gris_s10_7191"
ep="https://www.dr.dk/drtv/episode/gurli-gris_ep1_1001"
drtv_child "$canon" "$season"
drtv_child "$season" "$ep"
drtv_meta "$canon" '{"series":"Gurli Gris"}'
drtv_meta "$season" '{"series":"Gurli Gris","season_number":10}'
drtv_video "$ep" '{"id":"1001","ext":"mp4","series":"Gurli Gris","season_number":10,
  "episode_number":1,"episode":"En","title":"En"}'

# --- the redirect --------------------------------------------------------------
printf '%s\t301\t%s\n' "$bare" "$canon" >>"$CURL_MAP"
printf '%s\t200\t<html>the SPA</html>\n' "$canon" >>"$CURL_MAP"
run_drtv -d "$DRTV_LIB" -n "$bare"
assert_exit "exits 0" 0
assert_contains "the redirect is followed and reported" "$STDERR" \
  "resolved $bare -> $canon"
assert_contains "and the series is scanned" "$STDERR" "1 of 1 videos not on disk yet"

# --- the rel=canonical fallback ---------------------------------------------------
# The server answers 200 with the SPA page rather than redirecting, so the
# effective URL is unchanged and the canonical link in the body is what says
# where the show really lives.
drtv_init
drtv_child "$canon" "$season"
drtv_child "$season" "$ep"
drtv_meta "$canon" '{"series":"Gurli Gris"}'
drtv_meta "$season" '{"series":"Gurli Gris","season_number":10}'
drtv_video "$ep" '{"id":"1001","ext":"mp4","series":"Gurli Gris","season_number":10,
  "episode_number":1,"episode":"En","title":"En"}'
printf '%s\t200\t<html><head><link rel="canonical" href="/drtv/serie/gurli-gris_7190"/></head></html>\n' \
  "$bare" >>"$CURL_MAP"
run_drtv -d "$DRTV_LIB" -n "$bare"
assert_exit "exits 0" 0
assert_contains "the canonical link is used, made absolute" "$STDERR" \
  "resolved $bare -> $canon"

# --- neither ----------------------------------------------------------------------
drtv_init
printf '%s\t200\t<html>nothing useful</html>\n' "$bare" >>"$CURL_MAP"
run_drtv -d "$DRTV_LIB" -n "$bare"
assert_contains "an unresolvable bare ID is warned about" "$STDERR" \
  "could not resolve $bare to its canonical (slug) form"
assert_contains "with advice" "$STDERR" "use the URL from your browser's address bar"

# --- the site being unreachable altogether -------------------------------------------
drtv_init
printf '%s\t000\t-\n' "$bare" >>"$CURL_MAP"
run_drtv -d "$DRTV_LIB" -n "$bare"
assert_contains "a failed request warns rather than crashing" "$STDERR" \
  "could not resolve $bare"
