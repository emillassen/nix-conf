#!/usr/bin/env bash
# The library's parental rating: a "# rating: VALUE" line in drtv-series.txt
# puts <customrating> into every NFO the run writes - tvshow.nfo, the episode
# and the film alike. It is what lets a Jellyfin user with a rating limit and
# "block unrated items" see DR's children's shows at all, so a missing element
# is not cosmetic: the show silently vanishes from that profile. The line is
# hand-written like the rest of the file, and must stay a comment to the URL
# parser.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: the library rating"

serie="https://www.dr.dk/drtv/serie/testserie_7200"
season="https://www.dr.dk/drtv/saeson/testserie_s01_7201"
ep1="https://www.dr.dk/drtv/episode/testserie_afsnit_2001"
film="https://www.dr.dk/drtv/program/testfilm_3001"

scenario() {
  drtv_init
  drtv_meta "$serie" '{"series":"Testserie","description":"En testserie"}'
  drtv_meta "$season" '{"series":"Testserie","season_number":1}'
  drtv_child "$serie" "$season"
  drtv_child "$season" "$ep1"
  drtv_video "$ep1" '{"id":"2001","ext":"mp4","series":"Testserie","season_number":1,
    "episode_number":1,"episode":"Afsnittet","title":"Afsnittet","duration":420}'
  drtv_video "$film" '{"id":"3001","ext":"mp4","title":"Testfilmen","release_year":1995}'
  lib="$DRTV_LIB"
  show="$lib/Testserie/tvshow.nfo"
  episode="$lib/Testserie/Season 01/Testserie - S01E01 - Afsnittet.nfo"
  movie="$lib/Testfilmen (1995)/Testfilmen (1995).nfo"
}

# --- a hand-edited file: CRLF, odd case and spacing, a look-alike comment ------
scenario
{
  printf '#  Rating:   G\r\n'
  printf '# ratings are decided per library\r\n'
  printf '%s\r\n' "$serie" "$film"
} >"$lib/drtv-series.txt"

RUN_CWD="$lib" run_drtv
RUN_CWD=""
assert_exit "exits 0" 0
assert_contains "the rating line is not taken for a URL" "$STDERR" "using 2 URLs from ./drtv-series.txt"
assert_file_contains "tvshow.nfo carries the rating" "$show" "<customrating>G</customrating>"
assert_file_contains "so does the episode's own NFO" "$episode" "<customrating>G</customrating>"
assert_file_contains "and the film's" "$movie" "<customrating>G</customrating>"
assert_not_contains "the CR does not end up in the value" "$(cat "$show" "$episode" "$movie")" $'\r'
assert_file_contains "the NFO stays locked" "$episode" "<lockdata>true</lockdata>"

# --- no rating line: the NFOs are exactly what they were before -----------------
scenario
printf '%s\n' "$serie" "$film" >"$lib/drtv-series.txt"
RUN_CWD="$lib" run_drtv
RUN_CWD=""
assert_exit "exits 0 without a rating" 0
assert_not_contains "no customrating element is invented" \
  "$(cat "$show" "$episode" "$movie")" "customrating"

# --- URLs on the command line still land in a rated library ----------------------
# Two rating lines: the last one counts. No space after the colon and a note
# after the value are both how people write these.
scenario
{
  printf '# rating: PG\n'
  printf '%s\n' "$serie"
  printf '#rating:DK-A   # older kids, allowed anyway\n'
} >"$lib/drtv-series.txt"
run_drtv -d "$lib" "$serie" "$film"
assert_exit "exits 0 with URLs given" 0
assert_file_contains "a URL from the command line gets the library's rating" \
  "$episode" "<customrating>DK-A</customrating>"
assert_file_contains "the film too" "$movie" "<customrating>DK-A</customrating>"
assert_not_contains "the earlier line lost" "$(cat "$show")" "<customrating>PG</customrating>"
assert_not_contains "the note after the value is not part of it" "$(cat "$show")" "older kids"

# --- the value is escaped like every other field ----------------------------------
scenario
printf '# rating: A&B<7\n%s\n' "$serie" >"$lib/drtv-series.txt"
RUN_CWD="$lib" run_drtv
RUN_CWD=""
assert_file_contains "an ampersand and angle bracket are escaped" "$show" \
  "<customrating>A&amp;B&lt;7</customrating>"
