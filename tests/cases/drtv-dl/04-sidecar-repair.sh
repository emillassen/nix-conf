#!/usr/bin/env bash
# An episode whose video is on disk but whose .nfo is not — an interrupted run,
# or a library older than the sidecars. It is neither skipped nor downloaded: it
# joins the --skip-download probe, which regenerates its sidecars for the cost
# of one extraction, and scanned_bases keeps it from being counted twice in the
# summary. Run with a trailing slash on -d, because that is what used to make
# the two halves of that bookkeeping stop agreeing.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: repairing a missing .nfo"

drtv_init
season="https://www.dr.dk/drtv/saeson/gurli-gris_s10_7191"
ep1="https://www.dr.dk/drtv/episode/gurli-gris_ep1_1001"
ep2="https://www.dr.dk/drtv/episode/gurli-gris_ep2_1002"
drtv_meta "$season" '{"series":"Gurli Gris","season_number":10}'
drtv_child "$season" "$ep1"
drtv_child "$season" "$ep2"
drtv_video "$ep1" '{"id":"1001","ext":"mp4","series":"Gurli Gris","season_number":10,
  "episode_number":1,"episode":"En","title":"En"}'
drtv_video "$ep2" '{"id":"1002","ext":"mp4","series":"Gurli Gris","season_number":10,
  "episode_number":2,"episode":"To","title":"To","description":"Anden episode"}'

lib="$DRTV_LIB"
d="$lib/Gurli Gris/Season 10"
mkdir -p "$d"
printf 'video one\n' >"$d/Gurli Gris - S10E01 - En.mp4"
printf '<episodedetails/>\n' >"$d/Gurli Gris - S10E01 - En.nfo"
printf 'video two\n' >"$d/Gurli Gris - S10E02 - To.mp4"
# ... and a file of the user's own, which nothing here may touch.
printf 'my notes\n' >"$lib/notes.txt"
before="$(stat -c %Y "$d/Gurli Gris - S10E02 - To.mp4")"

run_drtv -d "$lib/" "$season"

assert_exit "exits 0" 0
assert_contains "the scan reports both as present" "$STDERR" \
  "2 of 2 episodes already on disk; skipping those"
assert_contains "and singles out the one missing its sidecar" "$STDERR" \
  "1 episode(s) on disk have no .nfo; re-extracting just those"

assert_file_exists "the missing .nfo is written" "$d/Gurli Gris - S10E02 - To.nfo"
assert_contains "from DR's own metadata" "$(cat "$d/Gurli Gris - S10E02 - To.nfo")" \
  "<plot>Anden episode</plot>"
assert_eq "and the video file itself is untouched" "$before" \
  "$(stat -c %Y "$d/Gurli Gris - S10E02 - To.mp4")"

# One extraction, for the one episode that needed it.
assert_eq "exactly one extraction" 1 "$(drtv_extractions)"
assert_contains "of the right episode" "$(drtv_events)" "extract $ep2"
assert_contains "the other was skipped before extraction" "$(drtv_events)" "skip-pre $ep1"

# The counting. Both episodes were on disk and both were seen once; counting the
# repaired one again in the probe's tally would inflate both halves.
assert_contains "the summary counts each video once" "$STDERR" \
  "2 of 2 videos were already on disk"
assert_contains "and nothing was downloaded" "$STDERR" "downloaded 0 file(s)"

# The info.json sweep clears up after itself and leaves everything else alone.
assert_eq "no info.json survives the run" 0 \
  "$(find "$lib" -name '*.info.json' | grep -c '' || true)"
assert_file_exists "the user's own file is still there" "$lib/notes.txt"
assert_file_exists "and so are both videos" "$d/Gurli Gris - S10E02 - To.mp4"
