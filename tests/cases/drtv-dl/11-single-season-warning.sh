#!/usr/bin/env bash
# DRTV's site puts the *season* URL in the address bar while you browse a show,
# so subscribing to one season thinking it is the whole series is the easy
# mistake — and a silent one: the run succeeds, and only the seasons you never
# see are missing. check_single_season asks DR's page API how many seasons the
# show has and says so, and until now nothing exercised it, because it needs a
# production-cdn.dr-massive.com entry in the curl map that no case had.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: warning that a season URL is only one season"

api='https://production-cdn.dr-massive.com/api/page?*path=/saeson/gurli-gris_s10_7191'
serie="https://www.dr.dk/drtv/serie/gurli-gris_7190"
season="https://www.dr.dk/drtv/saeson/gurli-gris_s10_7191"
ep="https://www.dr.dk/drtv/episode/gurli-gris_ep1_1001"

# The shape of DR's answer, cut down to the four fields the jq program reads.
many_seasons='{"entries":[{"item":{"seasonNumber":10,"show":{"title":"Gurli Gris",
  "path":"/serie/gurli-gris_7190","seasons":{"items":[{"id":1},{"id":2},{"id":3}]}}}}]}'
one_season='{"entries":[{"item":{"seasonNumber":1,"show":{"title":"Gurli Gris",
  "path":"/serie/gurli-gris_7190","seasons":{"items":[{"id":1}]}}}}]}'

setup() {
  drtv_init
  drtv_child "$season" "$ep"
  drtv_meta "$season" '{"series":"Gurli Gris","season_number":10}'
  drtv_video "$ep" '{"id":"1001","ext":"mp4","series":"Gurli Gris","season_number":10,
    "episode_number":1,"episode":"En","title":"En"}'
}

# --- a season of a show that has more ----------------------------------------
setup
printf '%s\t200\t%s\n' "$api" "${many_seasons//$'\n'/}" >>"$CURL_MAP"
run_drtv -d "$DRTV_LIB" -n "$season"
assert_exit "exits 0" 0
assert_contains "it names the season and the show" "$STDERR" \
  "$season is only season 10 of \"Gurli Gris\", which has 3 seasons"
assert_contains "and gives the series URL that gets all of them" "$STDERR" \
  "use https://www.dr.dk/drtv/serie/gurli-gris_7190 to get every season"
assert_eq "one API request, not one per episode" 1 "$(stub_count curl-urls 'production-cdn')"

# The trailing-slash spelling is the same subscription; the API path is built by
# stripping the site prefix off the URL, so a trailing slash would otherwise be
# carried into the query and asked about a path DR does not have.
setup
printf '%s\t200\t%s\n' "$api" "${many_seasons//$'\n'/}" >>"$CURL_MAP"
run_drtv -d "$DRTV_LIB" -n "$season/"
assert_contains "-d URL with a trailing slash asks the same question" "$STDERR" \
  "which has 3 seasons"

# --- a show that really does have one season ---------------------------------
setup
printf '%s\t200\t%s\n' "$api" "${one_season//$'\n'/}" >>"$CURL_MAP"
run_drtv -d "$DRTV_LIB" -n "$season"
assert_exit "exits 0" 0
assert_not_contains "no warning for a genuinely single-season show" "$STDERR" "is only season"

# --- a series URL is not asked about at all ----------------------------------
setup
drtv_child "$serie" "$season"
drtv_meta "$serie" '{"series":"Gurli Gris"}'
run_drtv -d "$DRTV_LIB" -n "$serie"
assert_exit "exits 0" 0
assert_eq "a series URL costs no API request" 0 "$(stub_count curl-urls 'production-cdn')"
assert_not_contains "and no warning" "$STDERR" "is only season"

# --- DR's API unreachable ----------------------------------------------------
# The check is a courtesy; it must never be the reason a run fails. Nothing is
# declared for the API here, so the curl stub refuses the connection outright.
setup
run_drtv -d "$DRTV_LIB" -n "$season"
assert_exit "an unreachable API does not fail the run" 0
assert_not_contains "and invents no warning" "$STDERR" "is only season"
assert_contains "the scan still ran" "$STDERR" "1 of 1 videos not on disk yet"

# --- the warning survives to the end-of-run summary --------------------------
# An overnight run buries a warning printed at the start under thousands of
# progress lines, which is what the collected list at the end is for.
setup
printf '%s\t200\t%s\n' "$api" "${many_seasons//$'\n'/}" >>"$CURL_MAP"
run_drtv -d "$DRTV_LIB" "$season"
assert_exit "exits 0" 0
assert_contains "it is repeated in the summary" "$STDERR" \
  "drtv-dl:   warning: $season is only season 10"
