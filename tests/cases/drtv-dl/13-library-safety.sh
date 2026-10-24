#!/usr/bin/env bash
# The ways drtv-dl could misjudge, or damage, a library it shares with other
# things: another tool's info.json files, a library root that is a symlink, a
# sidecar or a video left empty by an interrupted write, a leftover info.json
# that does not parse, a finished video whose title happens to look like a
# per-format stream, and the two modes (-c, -n) that used to say "all done" when
# they had in fact been unable to look.
#
# None of this narrows the library-wide info.json sweep as such - that is a
# recorded decision (it is what converts an interrupted run's jsons on the next
# run). Filtering out jsons some other extractor wrote keeps that recovery path
# whole: an interrupted DR run's jsons are still DR's.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: what it may and may not touch in a shared library"

season="https://www.dr.dk/drtv/saeson/gurli-gris_s10_7191"
ep1="https://www.dr.dk/drtv/episode/gurli-gris_ep1_1001"

one_episode() {
  drtv_init
  drtv_meta "$season" '{"series":"Gurli Gris","season_number":10}'
  drtv_child "$season" "$ep1"
  drtv_video "$ep1" '{"id":"1001","ext":"mp4","series":"Gurli Gris","season_number":10,
    "episode_number":1,"episode":"En","title":"En","description":"Første episode"}'
  lib="$DRTV_LIB"
  d="$lib/Gurli Gris/Season 10"
}

# --- another tool's info.json -------------------------------------------------
one_episode
mkdir -p "$lib/YouTube"
printf 'a video\n' >"$lib/YouTube/Talk.mp4"
printf '{"id":"abc","extractor_key":"Youtube","title":"Talk"}\n' >"$lib/YouTube/Talk.info.json"
printf '{"id":"def","extractor_key":"Youtube","title":"Gone"}\n' >"$lib/YouTube/Gone.info.json"
cp "$lib/YouTube/Talk.info.json" "$TMP/talk.json"
run_drtv -d "$lib" "$season"
assert_exit "a library with foreign jsons: exits 0" 0
assert_files_identical "another extractor's info.json is left exactly as it was" \
  "$TMP/talk.json" "$lib/YouTube/Talk.info.json"
assert_file_exists "including one with no video beside it" "$lib/YouTube/Gone.info.json"
assert_file_missing "and no NFO is made up for it" "$lib/YouTube/Talk.nfo"
assert_file_exists "while DR's own episode gets its sidecar" "$d/Gurli Gris - S10E01 - En.nfo"
assert_eq "and DR's own info.json is cleared away as before" "" \
  "$(find "$d" -name '*.info.json' -print)"

# --- a library root that is a symlink ------------------------------------------
# find does not descend into a symlink given as its starting point unless told
# to, so both info.json sweeps saw nothing: no NFO, and the jsons left behind.
one_episode
mv "$lib" "$TMP/real-library"
ln -s "$TMP/real-library" "$lib"
run_drtv -d "$lib" "$season"
assert_exit "a symlinked root: exits 0" 0
assert_file_exists "the episode is downloaded through it" "$d/Gurli Gris - S10E01 - En.mp4"
assert_file_exists "and gets its NFO" "$d/Gurli Gris - S10E01 - En.nfo"
assert_eq "with no info.json left behind" "" "$(find -L "$lib" -name '*.info.json' -print)"
rm -f "$lib"

# --- an NFO an interrupted write left empty -------------------------------------
# The redirect truncates before jq has written a byte, so a run killed in
# between leaves a zero-length NFO - which the scan used to accept as the
# sidecar, archiving the episode so nothing would ever repair it.
one_episode
mkdir -p "$d"
printf 'video one\n' >"$d/Gurli Gris - S10E01 - En.mp4"
: >"$d/Gurli Gris - S10E01 - En.nfo"
run_drtv -d "$lib" "$season"
assert_exit "an empty NFO: exits 0" 0
assert_contains "it is treated as missing" "$STDERR" "1 episode(s) on disk have no .nfo"
assert_file_contains "and written properly" "$d/Gurli Gris - S10E01 - En.nfo" \
  "<plot>Første episode</plot>"

# --- a leftover info.json that does not parse ------------------------------------
# jq failing on it was a bare command under set -e: the run ended there, with
# no summary, and the redirect had already emptied the good NFO it was writing.
one_episode
mkdir -p "$d"
printf 'video one\n' >"$d/Gurli Gris - S10E01 - En.mp4"
printf '<episodedetails><title>En</title></episodedetails>\n' >"$d/Gurli Gris - S10E01 - En.nfo"
cp "$d/Gurli Gris - S10E01 - En.nfo" "$TMP/good.nfo"
printf '{"id":"1001","extractor_key":"DRTV","title":' >"$d/Gurli Gris - S10E01 - En.info.json"
run_drtv -d "$lib" "$season"
assert_contains "the run still reaches its summary" "$STDERR" "---- run summary ----"
assert_files_identical "the NFO it would have replaced is intact" \
  "$TMP/good.nfo" "$d/Gurli Gris - S10E01 - En.nfo"
assert_contains "and the unreadable json is named" "$STDERR" "Gurli Gris - S10E01 - En.info.json"

# A json that parses and is DR's, but that the NFO filter chokes on (a string
# where a number belongs: `.duration / 60` is an error in jq). This is the one
# that actually reaches the write, and the redirect used to have emptied the
# NFO before jq gave up.
one_episode
mkdir -p "$d"
printf 'video one\n' >"$d/Gurli Gris - S10E01 - En.mp4"
cp "$TMP/good.nfo" "$d/Gurli Gris - S10E01 - En.nfo"
printf '{"id":"1001","extractor_key":"DRTV","series":"Gurli Gris","episode":"En","duration":"lang"}\n' \
  >"$d/Gurli Gris - S10E01 - En.info.json"
run_drtv -d "$lib" "$season"
assert_contains "a json the filter rejects: the summary is reached" "$STDERR" "---- run summary ----"
assert_files_identical "the NFO is kept as it was" "$TMP/good.nfo" "$d/Gurli Gris - S10E01 - En.nfo"
assert_contains "and the failure is named" "$STDERR" "could not turn Gurli Gris/Season 10/Gurli Gris - S10E01 - En.info.json into"
assert_eq "with no .tmp left behind" "" "$(find "$lib" -name '*.tmp' -print)"

# --- an empty video --------------------------------------------------------------
# yt-dlp takes any file at the final name for "already downloaded", whatever
# its size, so an empty one counted as present for good. Nothing is lost by
# removing a file with nothing in it, and that is what lets yt-dlp fetch it.
one_episode
mkdir -p "$d"
: >"$d/Gurli Gris - S10E01 - En.mp4"
printf '<episodedetails/>\n' >"$d/Gurli Gris - S10E01 - En.nfo"
run_drtv -d "$lib" "$season"
assert_exit "an empty video: exits 0" 0
assert_contains "it is not counted as on disk" "$STDERR" "0 of 1 episodes already on disk"
assert_file_contains "and is downloaded again" "$d/Gurli Gris - S10E01 - En.mp4" "video bytes for 1001"

# --- -c and a finished video that looks like a stream ----------------------------
one_episode
mkdir -p "$d"
printf 'a finished video\n' >"$d/Gurli Gris - S10E01 - Kamera.f1.mp4"
printf '<episodedetails/>\n' >"$d/Gurli Gris - S10E01 - Kamera.f1.nfo"
printf 'a stream\n' >"$d/Gurli Gris - S10E02 - To.f137.mp4"
run_drtv -d "$lib" -c
assert_exit "-c exits 0" 0
assert_file_exists "a finished video with its NFO is not a leftover" \
  "$d/Gurli Gris - S10E01 - Kamera.f1.mp4"
assert_file_missing "while a real per-format stream still goes" "$d/Gurli Gris - S10E02 - To.f137.mp4"

# --- -c on a library that is not there -------------------------------------------
run_drtv -d "$TMP/no-such-library" -c
assert_ne "-c on a missing library fails" 0 "$STATUS"
assert_not_contains "rather than reporting it clean" "$STDERR" "no leftover files"

# --- -n when a playlist cannot be read -------------------------------------------
one_episode
gone="https://www.dr.dk/drtv/saeson/taget-ned_s1_9999"
run_drtv -d "$lib" -n "$season" "$gone"
assert_ne "-n with an unreadable playlist fails" 0 "$STATUS"
assert_contains "it still lists what it could see" "$STDOUT" "Gurli Gris - S10E01 - En"
assert_contains "and says the answer is incomplete" "$STDERR" "could not be scanned"

# --- the same through the film probe ---------------------------------------------
# Films never appear in a playlist, so everything above that the playlist scan
# does for an episode, the --skip-download probe's sweep has to do for a film.
film="https://www.dr.dk/drtv/program/olsen-banden_12345"
one_film() {
  drtv_init
  drtv_video "$film" '{"id":"5001","ext":"mp4","title":"Olsen-banden","release_year":1968}'
  lib="$DRTV_LIB"
  fd="$lib/Olsen-banden (1968)"
  mkdir -p "$fd"
}

# On disk under a symlinked root: the probe's sweep has to see it there, or it
# never reaches the archive and the download pass takes the film up again.
one_film
printf 'the film\n' >"$fd/Olsen-banden (1968).mp4"
printf 'x' >"$fd/Olsen-banden (1968).mp4.part"
mv "$lib" "$TMP/real-films"
ln -s "$TMP/real-films" "$lib"
run_drtv -d "$lib" "$film"
assert_exit "a film under a symlinked root: exits 0" 0
assert_contains "the probe finds it on disk" "$STDERR" "1 of 1 rechecked videos already on disk"
assert_not_contains "so the download pass leaves it alone" "$(drtv_events)" "already-downloaded $film"
assert_contains "and the leftover beside it is still reported" "$STDERR" "1 leftover file(s)"
rm -f "$lib"

# Someone else's video and json in the library do not join the probe's tally.
one_film
printf 'the film\n' >"$fd/Olsen-banden (1968).mp4"
mkdir -p "$lib/YouTube"
printf 'a video\n' >"$lib/YouTube/Talk.mp4"
printf '{"id":"abc","extractor_key":"Youtube","title":"Talk"}\n' >"$lib/YouTube/Talk.info.json"
run_drtv -d "$lib" "$film"
assert_contains "only DR's own videos are counted" "$STDERR" "1 of 1 rechecked videos already on disk"

# An empty film is fetched again, like an empty episode.
one_film
: >"$fd/Olsen-banden (1968).mp4"
run_drtv -d "$lib" "$film"
assert_exit "an empty film: exits 0" 0
assert_file_contains "is downloaded again" "$fd/Olsen-banden (1968).mp4" "video bytes for 5001"
