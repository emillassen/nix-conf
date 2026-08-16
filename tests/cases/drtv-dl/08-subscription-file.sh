#!/usr/bin/env bash
# The drtv-series.txt parser. It is what makes "cd /mnt/series && drtv-dl" the
# whole workflow, and the file is hand-edited, so every way a hand-edited file
# can be odd has to be survivable.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/drtv.sh"
test_init "drtv-dl: the subscription file"

drtv_init
lib="$DRTV_LIB"
s1="https://www.dr.dk/drtv/saeson/one_s01_1"
s2="https://www.dr.dk/drtv/saeson/two_s01_2"
s3="https://www.dr.dk/drtv/saeson/three_s01_3"
for u in "$s1" "$s2" "$s3"; do
  drtv_playlist "$u"
  drtv_meta "$u" '{"series":"X","season_number":1}'
done

# CRLF line endings, a #-comment, an indented comment, a blank line, trailing
# text after a URL, and no final newline on the last line.
printf '%s\r\n' "$s1" >"$lib/drtv-series.txt"
{
  printf '\n'
  printf '# a comment\n'
  printf '   # an indented comment\n'
  printf '%s   # season two, keep an eye on it\n' "$s2"
  printf '%s' "$s3" # deliberately no trailing newline
} >>"$lib/drtv-series.txt"

RUN_CWD="$lib" run_drtv -n
RUN_CWD=""
assert_contains "all three URLs are read" "$STDERR" "using 3 URLs from ./drtv-series.txt"

# The CR must be stripped, or yt-dlp is handed a URL with a carriage return in
# it and reports a URL nobody typed.
assert_not_contains "no carriage return survives" "$(stub_log yt-dlp)" $'\r'
assert_contains "the commented URL comes through without its comment" \
  "$(stub_log yt-dlp)" "$s2 "
assert_not_contains "and without the note after it" "$(stub_log yt-dlp)" "keep an eye"

# --- a file of nothing but comments ---------------------------------------------
printf '# nothing here\n\n#  nor here\n' >"$lib/drtv-series.txt"
RUN_CWD="$lib" run_drtv -n
RUN_CWD=""
assert_exit "exits 1" 1
assert_contains "and says the file has no URLs" "$STDERR" "no URLs in ./drtv-series.txt"

# --- no file at all ----------------------------------------------------------------
rm -f "$lib/drtv-series.txt"
RUN_CWD="$lib" run_drtv -n
RUN_CWD=""
assert_exit "exits 1" 1
assert_contains "and says where it looked" "$STDERR" \
  "no URLs given and no ./drtv-series.txt to read them from"
