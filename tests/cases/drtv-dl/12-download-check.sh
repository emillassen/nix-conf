#!/usr/bin/env bash
# Every download is checked before it counts, because none of the ways a video
# arrives broken make yt-dlp complain: fragments that ran out early (the
# picture stops while the sound plays on), a video saved without its audio,
# and holes of zero bytes where a suspend lost the share's writes. A video that
# fails is moved to .drtv-broken/, which Jellyfin is told to skip, loses its
# sidecars, and fails the run; the next run downloads it again, and the copy
# that passes deletes the broken one. Around that: the download holds a sleep
# inhibitor, and gives up on a video whose fragments cannot all be fetched.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: checking each download"

drtv_init
season="https://www.dr.dk/drtv/saeson/gurli-gris_s10_7191"
ep_good="https://www.dr.dk/drtv/episode/gurli-gris_linser_1012"
ep_short="https://www.dr.dk/drtv/episode/gurli-gris_igloen_1013"
ep_corrupt="https://www.dr.dk/drtv/episode/gurli-gris_hr-tyr-skal-giftes_1014"
ep_silent="https://www.dr.dk/drtv/episode/gurli-gris_bryllupsdagen_1016"

drtv_meta "$season" '{"series":"Gurli Gris","season_number":10}'
episode() {
  local url="$1" id="$2" n="$3" title="$4" payload="${5:-}"
  drtv_video "$url" "$(jq -nc --arg id "$id" --argjson n "$n" --arg t "$title" --arg p "$payload" '
    {id: $id, ext: "mp4", series: "Gurli Gris", season_number: 10, episode_number: $n,
     episode: $t, title: $t, thumbnails: [{id: "tile", url: "https://img/\($id).jpg"}]}
    + (if $p == "" then {} else {payload: $p} end)')"
}
for u in "$ep_good" "$ep_short" "$ep_corrupt" "$ep_silent"; do drtv_child "$season" "$u"; done
episode "$ep_good" 1012 12 "Linser"
episode "$ep_short" 1013 13 "Igloen" "short-video"
episode "$ep_corrupt" 1014 14 "Hr Tyr skal giftes" "corrupt"
episode "$ep_silent" 1016 16 "Bryllupsdagen" "no-audio"

d="$DRTV_LIB/Gurli Gris/Season 10"
q="$DRTV_LIB/.drtv-broken/Gurli Gris/Season 10"
good="Gurli Gris - S10E12 - Linser"
short="Gurli Gris - S10E13 - Igloen"
corrupt="Gurli Gris - S10E14 - Hr Tyr skal giftes"
silent="Gurli Gris - S10E16 - Bryllupsdagen"

run_drtv -d "$DRTV_LIB" "$season"
assert_exit "a run with broken downloads fails" 1

assert_file_exists "the good episode stays" "$d/$good.mp4"
assert_file_exists "with its .nfo" "$d/$good.nfo"
assert_file_exists "and its thumb" "$d/$good-thumb.jpg"
for b in "$short" "$corrupt" "$silent"; do
  assert_file_missing "$b is taken out of the library" "$d/$b.mp4"
  assert_file_exists "into .drtv-broken, under the same path" "$q/$b.mp4"
  assert_file_missing "it gets no .nfo" "$d/$b.nfo"
  assert_file_missing "and its thumb goes" "$d/$b-thumb.jpg"
done
assert_file_exists "Jellyfin is told to skip the broken ones" "$DRTV_LIB/.drtv-broken/.ignore"

assert_contains "video that stops early is named, with both lengths" "$STDERR" \
  "Gurli Gris/Season 10/$short.mp4 failed its check: its video lasts 80s but its audio 305s"
assert_contains "so is a video that does not decode, with ffmpeg's first error" "$STDERR" \
  "$corrupt.mp4 failed its check: it does not decode cleanly ([h264 @ 0x5f458639cd00] Invalid NAL unit size (0 > 2682).)"
assert_contains "and one with no sound" "$STDERR" "$silent.mp4 failed its check: it has no audio stream"
assert_contains "the summary says the next run retries them" "$STDERR" \
  "moved to $DRTV_LIB/.drtv-broken - the next run downloads it again"
assert_contains "a broken video still takes its place in the progress" "$STDOUT" \
  "[2/4] BROKEN: Gurli Gris/Season 10/$short.mp4 - its video lasts 80s but its audio 305s; moved to .drtv-broken/"
assert_contains "and the good one is announced as before" "$STDOUT" "[1/4] finished: Gurli Gris/Season 10/$good.mp4"
assert_contains "only the good one counts as downloaded" "$STDERR" "downloaded 1 file(s)"
assert_contains "the summary points at what was set aside" "$STDERR" "3 broken video(s) kept in $DRTV_LIB/.drtv-broken"
assert_not_contains "yt-dlp is not blamed for it" "$STDERR" "yt-dlp exited with status"

assert_eq "every download is probed" 4 "$(stub_count ffprobe)"
assert_eq "only the ones whose streams look whole are decoded" 2 "$(stub_count ffmpeg)"
assert_contains "the download runs under a sleep inhibitor" "$(stub_log systemd-inhibit)" \
  "--what=sleep --who=drtv-dl --why=Downloading from DRTV yt-dlp --abort-on-unavailable-fragments"
assert_eq "and only the download holds one (plus the probe that it can)" 2 "$(stub_count systemd-inhibit)"

# --- the retry -------------------------------------------------------------------------
# DR serves good copies this time. The broken ones are missing from the library,
# so the playlist scan hands them to yt-dlp again; each copy that passes deletes
# the broken one it replaces.
episode "$ep_short" 1013 13 "Igloen"
episode "$ep_corrupt" 1014 14 "Hr Tyr skal giftes"
episode "$ep_silent" 1016 16 "Bryllupsdagen"
run_drtv -d "$DRTV_LIB" "$season"
assert_exit "the retry exits 0" 0
assert_contains "it skips the good one" "$STDERR" "1 of 4 episodes already on disk; skipping those"
assert_contains "and downloads the other three again" "$STDERR" "downloaded 3 file(s)"
for b in "$short" "$corrupt" "$silent"; do
  assert_file_exists "$b is back in the library" "$d/$b.mp4"
  assert_file_exists "with its .nfo" "$d/$b.nfo"
  assert_file_missing "and its broken copy is gone" "$q/$b.mp4"
done
assert_file_missing "the emptied directories go with them" "$DRTV_LIB/.drtv-broken/Gurli Gris"
assert_not_contains "the summary has nothing set aside to report" "$STDERR" "broken video(s) kept"
assert_contains "and no warnings" "$STDERR" "no warnings"

# --- a refused inhibitor ---------------------------------------------------------------
# Over SSH, polkit may not grant the lock, and systemd-inhibit then runs nothing
# at all. The download has to happen anyway, unprotected and saying so.
drtv_init
drtv_meta "$season" '{"series":"Gurli Gris","season_number":10}'
drtv_child "$season" "$ep_good"
episode "$ep_good" 1012 12 "Linser"
export SYSTEMD_INHIBIT_REFUSE=1
run_drtv -d "$DRTV_LIB" "$season"
unset SYSTEMD_INHIBIT_REFUSE
assert_exit "a refused inhibitor does not fail the run" 0
assert_file_exists "the episode is downloaded anyway" "$d/$good.mp4"
assert_contains "with a warning that it went unprotected" "$STDERR" \
  "could not block suspend (systemd-inhibit was refused)"
