#!/usr/bin/env bash
# The remaining modes and the ways a run can be asked for something impossible.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: modes and refusals"

drtv_init
serie="https://www.dr.dk/drtv/serie/gurli-gris_7190"
season="https://www.dr.dk/drtv/saeson/gurli-gris_s10_7191"
ep1="https://www.dr.dk/drtv/episode/gurli-gris_ep1_1001"
ep2="https://www.dr.dk/drtv/episode/gurli-gris_ep2_1002"
drtv_child "$serie" "$season"
drtv_child "$season" "$ep1"
drtv_child "$season" "$ep2"
drtv_meta "$serie" '{"series":"Gurli Gris"}'
drtv_meta "$season" '{"series":"Gurli Gris","season_number":10}'
drtv_video "$ep1" '{"id":"1001","ext":"mp4","series":"Gurli Gris","season_number":10,
  "episode_number":1,"episode":"En","title":"En"}'
drtv_video "$ep2" '{"id":"1002","ext":"mp4","series":"Gurli Gris","season_number":10,
  "episode_number":2,"episode":"To","title":"To"}'
lib="$DRTV_LIB"

# --- -l: the episode links, one per line -----------------------------------------
# A flat pass over a series yields its seasons, not its episodes, so the series
# is expanded first.
run_drtv -d "$lib" -l "$serie"
assert_exit "-l exits 0" 0
assert_eq "-l prints the episode links" "$ep1"$'\n'"$ep2" "$STDOUT"

# --- refusals ------------------------------------------------------------------------
run_drtv -d "$lib" -n -r "$serie"
assert_exit "combined modes are refused" 1
assert_contains "and named" "$STDERR" "-l, -n, -r and -c cannot be combined"

run_drtv -d "$lib" -Z "$serie"
assert_exit "an unknown option is refused" 1
assert_contains "and named" "$STDERR" "unknown option -Z"

run_drtv -d "$lib" -n not-a-url
assert_exit "-n with nothing to check is refused" 1
assert_contains "and says so" "$STDERR" "-n: no URLs to check"

# --- a film DR has taken down ----------------------------------------------------
# The probe answers nothing for it. Without a word that would read as "you have
# it already", which is the opposite of the truth.
gone="https://www.dr.dk/drtv/program/borte_999"
run_drtv -d "$lib" -n "$season" "$gone"
assert_contains "a URL that answers nothing is called out" "$STDERR" \
  "1 of 1 film/episode URLs could not be checked"
assert_contains "with the likely reason" "$STDERR" "gone from DR, or a URL that no longer resolves"

# --- -r: recheck everything, leave the videos alone -----------------------------------
run_drtv -d "$lib" "$serie"
assert_exit "the seeding run works" 0
d="$lib/Gurli Gris/Season 10"
before="$(stat -c %Y "$d/Gurli Gris - S10E01 - En.mp4")"
rm -f "$d/Gurli Gris - S10E01 - En.nfo" "$STUBLOG/ytdlp-events.log"

run_drtv -d "$lib" -r "$serie"
assert_exit "-r exits 0" 0
assert_eq "-r re-extracts every episode" 2 "$(drtv_extractions)"
assert_file_exists "-r regenerates the sidecars" "$d/Gurli Gris - S10E01 - En.nfo"
assert_eq "-r leaves the video files untouched" "$before" \
  "$(stat -c %Y "$d/Gurli Gris - S10E01 - En.mp4")"
assert_contains "-r says what it left alone" "$STDERR" \
  "2 of 2 rechecked videos already on disk; leaving their files untouched"
assert_contains "and downloads nothing" "$STDERR" "downloaded 0 file(s)"
