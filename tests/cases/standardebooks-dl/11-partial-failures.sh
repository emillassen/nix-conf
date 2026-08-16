#!/usr/bin/env bash
# The three ways a book can go wrong that are not a 404, a 429 or a 5xx — all of
# them ending in a file that must not be left looking downloaded.
#
# A 200 with an empty body is the nastiest of them: the request succeeded, so the
# site counted it against the quota, and a zero-byte file left in place would
# read as present to media_count's -e sibling and to every later run. It is why
# that test is -s and not -e, and why the .part is removed rather than moved.
#
# Plus migrate_layout's other half: a rename that cannot be made. The colliding
# case (07) is checked before the move; this is the move itself failing.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: empty bodies, refused formats and a failed rename"

se_init
se_book milne/now-we-are-six "Milne, A. A." "Now We Are Six"
se_book homer/the-iliad "Homer" "The Iliad"
se_book wells/the-time-machine "Wells, H. G." "The Time Machine"
se_sitemap

lib="$SE_LIB"
ledger="$lib/.standardebooks-dl-index.tsv"

# Rewriting the map rather than appending: several lines matching one glob are
# consumed in order, so an appended line would only be reached on a second hit.
drop_url() {
  grep -vF "$1" "$CURL_MAP" >"$TMP/map.new" && mv -- "$TMP/map.new" "$CURL_MAP"
}
dl='https://standardebooks.org/ebooks'

# Milne: the epub arrives, the azw3 comes back 200 with nothing in it.
drop_url 'milne_now-we-are-six.azw3'
printf '%s/milne/now-we-are-six/downloads/milne_now-we-are-six.azw3?*\t200\t-\n' \
  "$dl" >>"$CURL_MAP"

# Homer: the probe itself is an empty 200, so there is no OPF to read a name out
# of and the book cannot even be filed.
drop_url 'homer_the-iliad.epub?'
printf '%s/homer/the-iliad/downloads/homer_the-iliad.epub?*\t200\t-\n' "$dl" >>"$CURL_MAP"

# Wells: the site refuses outright with something that is neither 404 nor 5xx.
drop_url 'wells_the-time-machine.epub?'
printf '%s/wells/the-time-machine/downloads/wells_the-time-machine.epub?*\t403\t-\n' \
  "$dl" >>"$CURL_MAP"

run_sedl -d "$lib"
assert_exit "exits 0" 0

# --- the empty format --------------------------------------------------------
assert_file_exists "the formats that arrived are on disk" \
  "$lib/Milne, A. A/Now We Are Six/Now We Are Six.epub"
assert_file_exists "including the ones after the empty one" \
  "$lib/Milne, A. A/Now We Are Six/Now We Are Six.advanced.epub"
assert_file_missing "the empty one is not left behind" \
  "$lib/Milne, A. A/Now We Are Six/Now We Are Six.azw3"
assert_eq "and neither is its .part" "" "$(find "$lib" -name '*.part' -print)"
assert_contains "it is warned about by URL" "$STDERR" \
  "failed to fetch $dl/milne/now-we-are-six/downloads/milne_now-we-are-six.azw3"
assert_contains "and the book is reported incomplete, not downloaded" "$STDOUT" \
  "incomplete: Milne, A. A/Now We Are Six"

assert_file_contains "the book is still in the ledger" "$ledger" \
  "milne/now-we-are-six	Milne, A. A/Now We Are Six"

# --- the empty probe ---------------------------------------------------------
assert_contains "an unreadable probe says which step failed" "$STDERR" \
  "homer/the-iliad: could not read author/title from content.opf"
assert_eq "and leaves no directory guessed from the slug" "" "$(find "$lib" -maxdepth 1 -name 'Homer*' -print)"

# --- the refused format ------------------------------------------------------
assert_contains "a 403 is a failure, not a missing book" "$STDERR" \
  "wells/the-time-machine: failed to fetch compatible epub"
assert_not_contains "so it is not counted as offering no files" "$STDERR" \
  "the catalog lists them but offers no files"
assert_contains "the summary counts all three" "$STDERR" "3 ebook(s) failed - rerun to retry"

# --- what the site actually served counts against the quota ------------------
# A 200 is recorded whatever we end up doing with the bytes, because the site
# records what it served; a 403 is refused before it is recorded and costs
# nothing. Milne: the probe plus three formats (the epub is already on disk).
# Homer: the empty probe. Wells: nothing.
assert_eq "the ledger counts served responses, not useful ones" 5 \
  "$(awk 'END { print NR + 0 }' "$(quota_ledger)")"

# The ledger entry is what makes the next run cheap: it asks for the one format
# that is missing rather than for all four of a book it mostly has.
run_sedl -d "$lib" -n
assert_contains "a rerun would fetch just the missing format" "$STDOUT" \
  "milne/now-we-are-six (3/4 formats)"
assert_contains "and the two that never landed, whole" "$STDOUT" "homer/the-iliad"

# --- a rename that cannot be made --------------------------------------------
# The stuck book is deliberately not in this catalog. A run that also tried to
# download into the unwritable directory would die on the bare `mkdir -p` in the
# download loop long before reaching the summary, which is a separate matter from
# whether a failed rename is survivable.
se_init
se_book wells/the-time-machine "Wells, H. G." "The Time Machine"
se_sitemap
lib="$SE_LIB"
se_touch_book "$lib/Milne/A. A/Now We Are Six" "Now We Are Six"
# The target's parent exists but nothing may be created inside it, so mkdir -p
# is a no-op and the mv is what fails. (Running as root would defeat this, hence
# the guard: a case that quietly stopped testing anything is worse than a red one.)
mkdir -p "$lib/Milne, A. A"
chmod 500 "$lib/Milne, A. A"
if [[ -w "$lib/Milne, A. A" ]]; then
  fail "harness: could not make the target directory unwritable" \
    "the case has to run as a user the permission bits apply to"
else
  run_sedl -d "$lib"
  assert_exit "the run carries on past it" 0
  assert_contains "the failed rename is reported" "$STDERR" \
    "Milne/A. A/Now We Are Six: could not move to Milne, A. A/Now We Are Six"
  assert_contains "and counted as left behind" "$STDERR" \
    "moved 0 book(s) to Last, First/Title (1 left behind)"
  assert_file_exists "the book stays where it was" \
    "$lib/Milne/A. A/Now We Are Six/Now We Are Six.epub"
  assert_file_exists "and its author levels are not swept up" "$lib/Milne/A. A"
  assert_file_exists "the rest of the catalog is still synced" \
    "$lib/Wells, H. G/The Time Machine/The Time Machine.epub"
fi
chmod 700 "$lib/Milne, A. A"

# --- a book directory that cannot be written ---------------------------------
# The download loop creates each book's directory, and a bare `mkdir -p` under
# set -e ended the run right there: exit 1, no summary, no warning, and every
# book after it abandoned however far into a fortnight the run was. One
# directory with the wrong owner is an ordinary thing on the NAS share these
# libraries live on, and it is a single book's problem, not the catalog's.
se_init
se_book aaa/first "Aaa, A." "First Book"
se_book zzz/second "Zzz, Z." "Second Book"
se_sitemap
lib="$SE_LIB"
# The author directory as the script spells it: sanitize trims the trailing
# period, the same trim Calibre makes.
mkdir -p "$lib/Aaa, A"
chmod 500 "$lib/Aaa, A"
if [[ -w "$lib/Aaa, A" ]]; then
  fail "harness: could not make the author directory unwritable" \
    "the case has to run as a user the permission bits apply to"
else
  run_sedl -d "$lib"
  assert_exit "the run finishes rather than dying at the first bad directory" 0
  assert_contains "the book that could not be written is warned about" "$STDERR" \
    "aaa/first: could not write Aaa, A/First Book"
  assert_contains "and counted as a failure to retry" "$STDERR" "1 ebook(s) failed - rerun to retry"
  assert_file_exists "every later book is still fetched" \
    "$lib/Zzz, Z/Second Book/Second Book.epub"
  assert_contains "and the summary is reached at all" "$STDERR" "---- run summary ----"
  # Nothing half-written is left claiming the slug, so the next run retries it
  # from scratch rather than treating it as a book it already has.
  assert_not_contains "the failed book is not in the ledger" \
    "$(cat "$lib/.standardebooks-dl-index.tsv")" "aaa/first"
fi
chmod 700 "$lib/Aaa, A"
