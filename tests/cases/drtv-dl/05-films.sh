#!/usr/bin/env bash
# Films. They never appear in a playlist, so the cheap scan cannot see them and
# they are probed one request each instead; they carry no series/season/episode
# fields, so the one output template renders "Film (Year)//Film (Year).ext" and
# the empty component collapses; and their NFO is a <movie>, not an
# <episodedetails>.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: films"

drtv_init
film="https://www.dr.dk/drtv/program/olsen-banden_12345"
noyear="https://www.dr.dk/drtv/program/uden-aar_999"
drtv_video "$film" '{"id":"5001","ext":"mp4","title":"Olsen-banden","release_year":1968,
  "description":"Egon & banden","release_timestamp":1700000000,"duration":5400,
  "thumbnails":[{"id":"poster","url":"https://img/olsen.jpg"}]}'
drtv_video "$noyear" '{"id":"5002","ext":"mp4","title":"Uden År","description":"Ingen årstal"}'
printf 'https://img/olsen.jpg\t200\tposter bytes\n' >>"$CURL_MAP"

lib="$DRTV_LIB"

# --- -n: one probe each, and the empty season component is not shown ----------
run_drtv -d "$lib" -n "$film" "$noyear"
assert_exit "-n exits 0" 0
assert_contains "the film is listed missing" "$STDOUT" "Olsen-banden (1968)/Olsen-banden (1968)"
assert_not_contains "without the empty path component" "$STDOUT" "(1968)//"
assert_contains "a film with no year keeps just its title" "$STDOUT" "Uden År/Uden År"
assert_contains "and the count is right" "$STDERR" "2 of 2 videos not on disk yet"
assert_eq "-n downloads nothing" 0 "$(find "$lib" -name '*.mp4' | grep -c '' || true)"

# --- the real run --------------------------------------------------------------
run_drtv -d "$lib" "$film" "$noyear"
assert_exit "exits 0" 0
assert_file_exists "the film lands one level up, as Jellyfin wants" \
  "$lib/Olsen-banden (1968)/Olsen-banden (1968).mp4"
assert_file_exists "with its .nfo" "$lib/Olsen-banden (1968)/Olsen-banden (1968).nfo"

nfo="$(cat "$lib/Olsen-banden (1968)/Olsen-banden (1968).nfo")"
assert_contains "a film is a movie, not an episode" "$nfo" "<movie>"
assert_not_contains "and carries no season" "$nfo" "<season>"
assert_contains "it has a year" "$nfo" "<year>1968</year>"
assert_contains "and a premiered date rather than an aired one" "$nfo" "<premiered>2023-11-14</premiered>"
assert_contains "the plot is escaped" "$nfo" "Egon &amp; banden"
assert_contains "the runtime is whole minutes" "$nfo" "<runtime>90</runtime>"
assert_contains "and it is locked" "$nfo" "<lockdata>true</lockdata>"

assert_file_exists "DR's portrait poster is fetched for the film" \
  "$lib/Olsen-banden (1968)/poster.jpg"

nfo2="$(cat "$lib/Uden År/Uden År.nfo")"
assert_contains "a film with nothing but a title still gets an NFO" "$nfo2" "<movie>"
assert_contains "with that title" "$nfo2" "<title>Uden År</title>"
assert_not_contains "and no year element at all" "$nfo2" "<year>"
assert_not_contains "no premiered either" "$nfo2" "<premiered>"
assert_not_contains "and no runtime" "$nfo2" "<runtime>"
assert_file_missing "a film with no poster in its metadata gets none" "$lib/Uden År/poster.jpg"

# --- rerunning: the probe puts them in the archive ------------------------------
rm -f "$STUBLOG/ytdlp-events.log"
run_drtv -d "$lib" "$film" "$noyear"
assert_exit "the rerun exits 0" 0
assert_contains "both are recognised" "$STDERR" "2 of 2 rechecked videos already on disk"
assert_contains "the download run skips them" "$STDERR" "downloaded 0 file(s)"
# A film is unavoidably re-extracted once by the probe; what the archive buys is
# that the download pass does not extract it a second time.
assert_eq "two extractions, both in the probe" 2 "$(drtv_extractions)"
