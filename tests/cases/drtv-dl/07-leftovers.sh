#!/usr/bin/env bash
# -c and the leftover matcher. Every run reports what an interrupted run left
# behind; only -c removes it, because a .part-Frag file may belong to a second
# drtv-dl downloading into the same library right now.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: leftover scratch files"

drtv_init
lib="$DRTV_LIB"
d="$lib/Gurli Gris/Season 10"
mkdir -p "$d"

# What yt-dlp actually leaves behind.
leftovers=(
  "Ep.mp4.part"
  "Ep.mp4.part-Frag7"
  "Ep.mp4.ytdl"
  "Ep.mp4.temp"
  "Ep.fvideo_1"
  "Ep.faudio_2"
  "Ep.f137.mp4"
  "Ep.f251.webm"
)
# What must survive.
keepers=(
  "Ep.mp4"
  "Ep.nfo"
  "Ep-thumb.jpg"
  "Ep.srt"
  "Ep.foo.mp4"     # letters after the f, so not a per-format stream
  "Ep - 1.5.mp4"   # a dotted number that is not a format id
  "notes.txt"
)
for f in "${leftovers[@]}" "${keepers[@]}"; do printf 'x' >"$d/$f"; done

# An ordinary run reports them and removes nothing.
season="https://www.dr.dk/drtv/saeson/gurli-gris_s10_7191"
drtv_playlist "$season"
drtv_meta "$season" '{"series":"Gurli Gris","season_number":10}'
run_drtv -d "$lib" "$season"
assert_contains "an ordinary run reports the leftovers" "$STDERR" \
  "8 leftover file(s) from interrupted runs"
assert_contains "and says how to remove them" "$STDERR" "remove with: drtv-dl -d"
assert_file_exists "but removes nothing itself" "$d/Ep.mp4.part"

# -c removes exactly those, and reports each one library-relative even when -d
# was given with a trailing slash.
run_drtv -d "$lib/" -c
assert_exit "-c exits 0" 0
assert_contains "-c reports the count" "$STDERR" "removed 8 leftover file(s)"
assert_contains "-c names them relative to the library" "$STDOUT" \
  "removed Gurli Gris/Season 10/Ep.mp4.part"
assert_not_contains "not as absolute paths" "$STDOUT" "removed $lib/"
for f in "${leftovers[@]}"; do
  assert_file_missing "-c removed $f" "$d/$f"
done
for f in "${keepers[@]}"; do
  assert_file_exists "-c kept $f" "$d/$f"
done

run_drtv -d "$lib" -c
assert_contains "a second -c has nothing to do" "$STDERR" "no leftover files in"
