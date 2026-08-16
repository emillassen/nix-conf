#!/usr/bin/env bash
# A whole series, from nothing: Jellyfin-shaped paths, an .nfo and a thumb per
# episode, tvshow.nfo and posters for the series, and a progress line per file
# that is a position rather than a running total.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: downloading a series"

drtv_init
serie="https://www.dr.dk/drtv/serie/gurli-gris_7190"
season="https://www.dr.dk/drtv/saeson/gurli-gris_s10_7191"
ep1="https://www.dr.dk/drtv/episode/gurli-gris_slemme-skildpadde_1001"
ep2="https://www.dr.dk/drtv/episode/gurli-gris_snelandet_1002"

drtv_meta "$serie" '{"series":"Gurli Gris","description":"En gris & hendes familie",
  "thumbnails":[{"id":"poster","url":"https://img/poster.jpg"}]}'
drtv_meta "$season" '{"series":"Gurli Gris","season_number":10,"description":"Sæson 10",
  "thumbnails":[{"id":"poster","url":"https://img/s10.jpg"}]}'
drtv_child "$serie" "$season"
drtv_child "$season" "$ep1"
drtv_child "$season" "$ep2"
drtv_video "$ep1" '{"id":"1001","ext":"mp4","series":"Gurli Gris","season_number":10,
  "episode_number":1,"episode":"Gurli Gris: Slemme skildpadde","title":"Gurli Gris: Slemme skildpadde",
  "description":"Gurli & George leger","release_timestamp":1700000000,"duration":425,
  "thumbnails":[{"id":"tile","url":"https://img/ep1.jpg"}]}'
drtv_video "$ep2" '{"id":"1002","ext":"mp4","series":"Gurli Gris","season_number":10,
  "episode_number":2,"episode":"Gurli Gris: Snelandet","title":"Gurli Gris: Snelandet",
  "description":"Sne <og> is","release_timestamp":1700100000,"duration":430,
  "thumbnails":[{"id":"tile","url":"https://img/ep2.jpg"}]}'

run_drtv -d "$DRTV_LIB" "$serie"
assert_exit "exits 0" 0

d="$DRTV_LIB/Gurli Gris/Season 10"
assert_file_exists "the episode lands where Jellyfin looks" \
  "$d/Gurli Gris - S10E01 - Slemme skildpadde.mp4"
assert_file_exists "the series prefix is stripped from the title" \
  "$d/Gurli Gris - S10E02 - Snelandet.mp4"
assert_file_exists "with a thumb beside it" "$d/Gurli Gris - S10E01 - Slemme skildpadde-thumb.jpg"
assert_file_exists "and an .nfo" "$d/Gurli Gris - S10E01 - Slemme skildpadde.nfo"

nfo="$(cat "$d/Gurli Gris - S10E01 - Slemme skildpadde.nfo")"
assert_contains "an episode is episodedetails" "$nfo" "<episodedetails>"
assert_contains "with the season" "$nfo" "<season>10</season>"
assert_contains "and the episode number" "$nfo" "<episode>1</episode>"
assert_contains "the title has its series prefix stripped here too" "$nfo" \
  "<title>Slemme skildpadde</title>"
assert_contains "an ampersand in the plot is escaped" "$nfo" "Gurli &amp; George leger"
assert_contains "the aired date comes from the release timestamp" "$nfo" "<aired>2023-11-14</aired>"
assert_contains "the runtime is whole minutes" "$nfo" "<runtime>7</runtime>"
assert_contains "and Jellyfin is told to keep DR's metadata" "$nfo" "<lockdata>true</lockdata>"
assert_contains "angle brackets are escaped" \
  "$(cat "$d/Gurli Gris - S10E02 - Snelandet.nfo")" "Sne &lt;og&gt; is"

assert_file_exists "the series gets a tvshow.nfo" "$DRTV_LIB/Gurli Gris/tvshow.nfo"
assert_contains "carrying the show description, escaped" \
  "$(cat "$DRTV_LIB/Gurli Gris/tvshow.nfo")" "En gris &amp; hendes familie"
assert_file_exists "and a poster" "$DRTV_LIB/Gurli Gris/poster.jpg"
assert_file_exists "and a season poster" "$DRTV_LIB/Gurli Gris/season10-poster.jpg"

# The info.jsons never outlive the run.
assert_eq "no info.json is left behind" 0 \
  "$(find "$DRTV_LIB" -name '*.info.json' | grep -c '' || true)"

assert_contains "progress is a position" "$STDOUT" "[1/2] finished:"
assert_contains "and drops the library root" "$STDOUT" "Gurli Gris/Season 10/"
assert_contains "the summary counts the files" "$STDERR" "downloaded 2 file(s)"
assert_contains "and reports no warnings" "$STDERR" "no warnings"

# --- a rerun ------------------------------------------------------------------------
# The playlist scan sees both episodes on disk with their .nfo, so both go into
# the throwaway download archive and cost no extraction at all.
rm -f "$STUBLOG/ytdlp-events.log"
run_drtv -d "$DRTV_LIB" "$serie"
assert_exit "the rerun exits 0" 0
assert_contains "it says what it is skipping" "$STDERR" \
  "2 of 2 episodes already on disk; skipping those"
assert_eq "and extracts nothing" 0 "$(drtv_extractions)"
assert_contains "both were matched before extraction, on the URL slug" \
  "$(drtv_events)" "skip-pre $ep1"
assert_contains "the summary says nothing was downloaded" "$STDERR" "downloaded 0 file(s)"
