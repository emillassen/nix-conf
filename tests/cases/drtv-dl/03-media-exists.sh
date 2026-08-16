#!/usr/bin/env bash
# media_exists decides whether an episode is already downloaded, which decides
# whether it is downloaded again. Its rule is "a file with this base name and a
# single-token extension that is not a known sidecar", and every part of that
# matters: yt-dlp's own leftovers (.part, .part-Frag3, .f137.mp4, .ytdl) must
# not count, and neither must the sidecars this script writes itself.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: media_exists"

drtv_init
extract_funcs "$DRTVDL" "$TMP/fns.sh" media_exists
# shellcheck source=/dev/null
. "$TMP/fns.sh"

d="$TMP/lib"
mkdir -p "$d"

check() {
  local label="$1" base="$2" want="$3"
  local rc=0
  media_exists "$d/$base" || rc=1
  if [[ "$want" == yes ]]; then
    assert_eq "$label" 0 "$rc"
  else
    assert_eq "$label" 1 "$rc"
  fi
}

place() {
  rm -f "$d"/*
  local f
  for f in "$@"; do : >"$d/$f"; done
}

place
check "nothing on disk" "Ep" no

place "Ep.mp4"
check "a plain video counts" "Ep" yes
place "Ep.mkv"
check "so does another container" "Ep" yes

# yt-dlp's scratch files from an interrupted run. It names them after the
# *final* filename, so they all carry two extension tokens and the single-token
# rule is what rules them out.
place "Ep.mp4.part"
check "a partial download does not count" "Ep" no
place "Ep.mp4.part-Frag3"
check "nor a fragment" "Ep" no
place "Ep.mp4.ytdl"
check "nor the resume data" "Ep" no
place "Ep.f137.mp4"
check "nor an unmerged per-format stream" "Ep" no
place "Ep.mp4.part" "Ep.mp4.ytdl"
check "nor the two of them together" "Ep" no

# The sidecars this script writes.
place "Ep.nfo"
check "an .nfo alone is not a video" "Ep" no
for ext in jpg jpeg png webp; do
  place "Ep.$ext"
  check "nor a .$ext" "Ep" no
done

# Subtitles and notes a user may keep next to their library. A library of
# Danish television is exactly where external .srt files turn up, and treating
# one as the video means the episode is never fetched.
for ext in srt vtt ass ssa sub txt; do
  place "Ep.$ext"
  check "nor a .$ext" "Ep" no
done

# A title carrying glob metacharacters. The glob is "$1".* with the variable
# quoted, so these match literally.
place "Titel [DR2].mp4"
check "square brackets in a title" "Titel [DR2]" yes
place "Star * Title.mp4"
check "an asterisk in a title" "Star * Title" yes
place "Who? Me.mp4"
check "a question mark in a title" "Who? Me" yes

# A video and its sidecars together: still a video.
place "Ep.mp4" "Ep.nfo" "Ep-thumb.jpg"
check "video plus sidecars" "Ep" yes
