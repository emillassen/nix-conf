#!/usr/bin/env bash
# DR fills the poster slot with one generic play-button placeholder for every
# show without portrait artwork — most of the children's series — and the
# playlist thumbnail download writes that placeholder over poster.jpg on every
# run. The real artwork for those shows is in the square/tile/wallpaper slots.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: posters"

drtv_init
season="https://www.dr.dk/drtv/saeson/gurli-gris_s10_7191"
ep1="https://www.dr.dk/drtv/episode/gurli-gris_ep1_1001"
ph="https://asset.dr-massive.com/img?ImageId='16099618'&Format='png'"
square="https://asset.dr-massive.com/img?ImageId='222'&Format='png'"
tile="https://asset.dr-massive.com/img?ImageId='333'&Format='png'"
wall="https://asset.dr-massive.com/img?ImageId='444'&Format='png'"

drtv_meta "$season" "$(jq -n --arg ph "$ph" --arg sq "$square" --arg ti "$tile" --arg wa "$wall" '
  {series:"Gurli Gris", season_number:10, thumbnails:[
    {id:"wallpaper", url:$wa}, {id:"tile", url:$ti},
    {id:"poster", url:$ph}, {id:"square", url:$sq}]}')"
drtv_child "$season" "$ep1"
drtv_video "$ep1" '{"id":"1001","ext":"mp4","series":"Gurli Gris","season_number":10,
  "episode_number":1,"episode":"En","title":"En"}'

# The replacement is asked for as a jpg, because the file keeps its .jpg name.
printf "%s\t200\tsquare artwork\n" "${square//Format=\'png\'/Format=\'jpg\'}" >>"$CURL_MAP"

lib="$DRTV_LIB"
run_drtv -d "$lib" "$season"
assert_exit "exits 0" 0

assert_contains "the placeholder is recognised and replaced" "$STDOUT" \
  "replaced placeholder poster"
assert_file_contains "with the square artwork, not the placeholder" \
  "$lib/Gurli Gris/season10-poster.jpg" "square artwork"
assert_contains "asked for as a jpg" "$(stub_log curl-urls)" "Format='jpg'"
assert_not_contains "the png was never fetched" "$(stub_log curl-urls)" "ImageId='222'&Format='png'"
assert_not_contains "no warning about a poster it could not replace" "$STDERR" \
  "could not replace placeholder poster"
assert_not_contains "and neither was the tile" "$(stub_log curl-urls)" "ImageId='333'"

# Only a season playlist was processed, so its poster stands in for the series'.
assert_file_exists "the season poster is promoted to the series poster" "$lib/Gurli Gris/poster.jpg"
assert_file_contains "and it is the replaced one" "$lib/Gurli Gris/poster.jpg" "square artwork"
assert_file_exists "a season-only run still writes tvshow.nfo" "$lib/Gurli Gris/tvshow.nfo"

# --- an existing series poster is not overwritten by a season one --------------
printf 'the real series poster\n' >"$lib/Gurli Gris/poster.jpg"
run_drtv -d "$lib" "$season"
assert_file_contains "an existing poster stays" "$lib/Gurli Gris/poster.jpg" \
  "the real series poster"

# --- a show with no thumbnails at all -------------------------------------------
drtv_init
s2="https://www.dr.dk/drtv/saeson/bar_s01_1"
e2="https://www.dr.dk/drtv/episode/bar_ep1_2"
drtv_meta "$s2" '{"series":"Bar","season_number":1}'
drtv_child "$s2" "$e2"
drtv_video "$e2" '{"id":"2","ext":"mp4","series":"Bar","season_number":1,
  "episode_number":1,"episode":"En","title":"En"}'
run_drtv -d "$DRTV_LIB" "$s2"
assert_exit "a show with no artwork still exits 0" 0
assert_file_exists "and its episode arrives" "$DRTV_LIB/Bar/Season 01/Bar - S01E01 - En.mp4"
assert_file_missing "with no poster invented" "$DRTV_LIB/Bar/poster.jpg"
assert_contains "and no warning about it" "$STDERR" "no warnings"
