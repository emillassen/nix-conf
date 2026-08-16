#!/usr/bin/env bash
# Awkward library roots. All three of these are things a real -d can be:
#
#   an apostrophe   the progress script is generated with the path baked into
#                   single quotes, so one apostrophe closes the quoting and
#                   leaves a script that does not parse — every progress line of
#                   an overnight run dies, silently
#   a per-cent      yt-dlp expands %(...)s anywhere in an -o template, including
#                   in the part that is meant to be a literal directory
#   a trailing /    the template then yields "dir//Series" while find yields
#                   "dir/Series", so the two never match up
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: awkward library roots"

drtv_init
season="https://www.dr.dk/drtv/saeson/gurli-gris_s10_7191"
ep1="https://www.dr.dk/drtv/episode/gurli-gris_slemme-skildpadde_1001"
drtv_meta "$season" '{"series":"Gurli Gris","season_number":10}'
drtv_child "$season" "$ep1"
drtv_video "$ep1" '{"id":"1001","ext":"mp4","series":"Gurli Gris","season_number":10,
  "episode_number":1,"episode":"Slemme skildpadde","title":"Slemme skildpadde"}'

run_in() {
  local root="$1"
  shift
  mkdir -p "$root"
  rm -f "$STUBLOG/ytdlp-events.log"
  run_drtv -d "$root" "$@" "$season"
}

# --- an apostrophe in the path -------------------------------------------------
lib="$TMP/Emil's videos"
run_in "$lib"
assert_exit "exits 0" 0
assert_file_exists "the episode still lands" \
  "$lib/Gurli Gris/Season 10/Gurli Gris - S10E01 - Slemme skildpadde.mp4"
assert_contains "and the run announces it" "$STDOUT" \
  "finished: Gurli Gris/Season 10/Gurli Gris - S10E01 - Slemme skildpadde.mp4"
assert_contains "the summary counts it" "$STDERR" "downloaded 1 file(s)"
assert_not_contains "nothing in the progress script failed to parse" "$STDERR" \
  "Syntax error"
assert_not_contains "nor did it go unterminated" "$STDERR" "unexpected EOF"

# --- a per-cent sign in the path -------------------------------------------------
lib="$TMP/100%% done"
run_in "$lib"
assert_exit "a bare %% exits 0" 0
assert_file_exists "and stays literal" \
  "$lib/Gurli Gris/Season 10/Gurli Gris - S10E01 - Slemme skildpadde.mp4"

lib="$TMP/lit %(id)s dir"
run_in "$lib"
assert_exit "a literal template in the path exits 0" 0
assert_file_exists "and is not expanded" \
  "$lib/Gurli Gris/Season 10/Gurli Gris - S10E01 - Slemme skildpadde.mp4"
assert_file_missing "so no directory named after the video id appears" "$TMP/lit 1001 dir"

# --- a trailing slash on -d ----------------------------------------------------
# The episode is already on disk from the run above, so the scan must recognise
# it. With "dir//Series" from the template and "dir/Series" from find, the
# scanned_bases lookup misses and the summary counts the same episode twice.
rm -f "$STUBLOG/ytdlp-events.log"
run_drtv -d "$lib/" "$season"
assert_exit "a trailing slash exits 0" 0
assert_contains "the episode is recognised as already on disk" "$STDERR" \
  "1 of 1 episodes already on disk"
assert_eq "so nothing is extracted" 0 "$(drtv_extractions)"
assert_not_contains "and the summary does not double-count it" "$STDERR" "of 2 videos"
assert_contains "it reports one video, once" "$STDERR" "1 of 1 videos were already on disk"
