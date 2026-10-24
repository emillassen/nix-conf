#!/usr/bin/env bash
# The layout migration and the ledger have to agree about where a book is. The
# migration moves directories; migrate_index then rewrites the ledger's legacy
# paths, and it used to rewrite every one of them whether or not its directory
# had actually moved. A book whose move collided or failed was then looked for
# at a path it is not at, and fetched again into it — four files of a 100-per-6h
# budget for a book already complete on disk, and two copies of it afterwards.
#
# The other half is the migration's own `mkdir -p`, which was bare under set -e
# while the `mv` beside it was guarded: one author path that would not take a
# directory ended the run before a single book was looked at.
#
# And fetch_one's final rename, which is the same class: it ran unchecked under
# `|| ok=0`, where errexit is off, so a format that never reached its name was
# reported downloaded.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: the ledger follows only migrations that happened"

dl='https://standardebooks.org/ebooks'

# --- a collision: the new path exists, the complete book is still legacy -------
se_init
se_book milne/now-we-are-six "Milne, A. A." "Now We Are Six"
se_book wells/the-time-machine "Wells, H. G." "The Time Machine"
se_sitemap
lib="$SE_LIB"
ledger="$lib/.standardebooks-dl-index.tsv"
se_touch_book "$lib/Milne/A. A/Now We Are Six" "Now We Are Six"
# A partial copy someone started by hand: one format of four.
mkdir -p "$lib/Milne, A. A/Now We Are Six"
printf 'by hand\n' >"$lib/Milne, A. A/Now We Are Six/Now We Are Six.epub"
printf 'milne/now-we-are-six\tMilne/A. A/Now We Are Six\n' >"$ledger"

run_sedl -d "$lib"
assert_exit "exits 0" 0
assert_contains "the collision is reported" "$STDERR" "already exists - left in place, merge it by hand"
assert_file_contains "the ledger still points at the book that is complete" "$ledger" \
  "milne/now-we-are-six	Milne/A. A/Now We Are Six"
assert_eq "nothing of it is fetched again" 0 "$(stub_count curl milne_now-we-are-six)"
assert_file_missing "and the hand-made copy is not filled in behind its back" \
  "$lib/Milne, A. A/Now We Are Six/Now We Are Six.azw3"
assert_not_contains "no ledger path is reported rewritten" "$STDERR" "ledger path(s) updated"
assert_file_exists "the rest of the catalog still syncs" \
  "$lib/Wells, H. G/The Time Machine/The Time Machine.epub"

# --- a move made by an earlier run that died before the ledger followed --------
# The directory is already in the new layout and the ledger still says legacy.
# Rewriting only what *this* run moved would leave that entry stale for ever, so
# the rule is "rewrite unless the legacy directory still holds the book".
se_init
se_book milne/now-we-are-six "Milne, A. A." "Now We Are Six"
se_sitemap
lib="$SE_LIB"
ledger="$lib/.standardebooks-dl-index.tsv"
se_touch_book "$lib/Milne, A. A/Now We Are Six" "Now We Are Six"
printf 'milne/now-we-are-six\tMilne/A. A/Now We Are Six\n' >"$ledger"

run_sedl -d "$lib"
assert_exit "an orphaned legacy entry: exits 0" 0
assert_file_contains "it is rewritten to where the book is" "$ledger" \
  "milne/now-we-are-six	Milne, A. A/Now We Are Six"
assert_eq "and the book is not fetched" 0 "$(stub_count curl milne_now-we-are-six)"
assert_file_missing "nor a legacy directory recreated" "$lib/Milne"

# --- the migration's mkdir fails ----------------------------------------------
# A regular file where the new author directory has to go: mkdir -p cannot get
# past it, whoever runs the script.
se_init
se_book milne/now-we-are-six "Milne, A. A." "Now We Are Six"
se_book wells/the-time-machine "Wells, H. G." "The Time Machine"
se_sitemap
lib="$SE_LIB"
ledger="$lib/.standardebooks-dl-index.tsv"
se_touch_book "$lib/Milne/A. A/Now We Are Six" "Now We Are Six"
printf 'milne/now-we-are-six\tMilne/A. A/Now We Are Six\n' >"$ledger"
printf 'not a directory\n' >"$lib/Milne, A. A"

run_sedl -d "$lib"
assert_exit "an obstructed author path: the run carries on" 0
assert_contains "the book is reported as not moved" "$STDERR" \
  "Milne/A. A/Now We Are Six: could not move to Milne, A. A/Now We Are Six"
assert_contains "and counted as left behind" "$STDERR" \
  "moved 0 book(s) to Last, First/Title (1 left behind)"
assert_file_contains "its ledger entry stays where the book is" "$ledger" \
  "milne/now-we-are-six	Milne/A. A/Now We Are Six"
assert_eq "it is not fetched again" 0 "$(stub_count curl milne_now-we-are-six)"
assert_file_exists "the rest of the catalog still syncs" \
  "$lib/Wells, H. G/The Time Machine/The Time Machine.epub"
assert_contains "and the summary is reached" "$STDERR" "---- run summary ----"

# --- a format that downloads but cannot be renamed into place ------------------
# An mv that refuses one destination and passes everything else through to the
# real one: the transfer succeeds, the .part is on disk, and the final rename is
# the only thing that fails.
se_init
se_book wells/the-time-machine "Wells, H. G." "The Time Machine"
se_sitemap
lib="$SE_LIB"
real_mv="$(PATH="$HOST_PATH" command -v mv)"
cat >"$STUBDIR/mv" <<EOF
#!$HARNESS_BASH
for a in "\$@"; do
  [[ "\$a" == *'The Time Machine.azw3' ]] && { echo "mv: cannot move: Permission denied" >&2; exit 1; }
done
exec "$real_mv" "\$@"
EOF
chmod +x "$STUBDIR/mv"

run_sedl -d "$lib"
assert_exit "a failed rename: exits 0" 0
assert_contains "the book is reported incomplete" "$STDOUT" \
  "incomplete: Wells, H. G/The Time Machine"
assert_not_contains "not downloaded" "$STDOUT" "downloaded: Wells, H. G/The Time Machine"
assert_contains "the format is warned about" "$STDERR" "The Time Machine.azw3"
assert_contains "and counted as a failure to retry" "$STDERR" "1 ebook(s) failed - rerun to retry"
assert_file_missing "the format is not on disk" "$lib/Wells, H. G/The Time Machine/The Time Machine.azw3"
assert_eq "and no .part is left beside it" "" "$(find "$lib" -name '*.part' -print)"
assert_file_exists "the formats after it still arrive" \
  "$lib/Wells, H. G/The Time Machine/The Time Machine.advanced.epub"

# --- a ledger that stops taking writes ----------------------------------------
# The append after a new book's probe was bare under set -e, so a ledger gone
# read-only ended the run there. It is a cache - the next run recovers the entry
# from the epub - so a failed append is a warning, not the end of the catalog.
se_init
se_book aaa/first "Aaa, A." "First Book"
se_book zzz/second "Zzz, Z." "Second Book"
se_sitemap
lib="$SE_LIB"
ledger="$lib/.standardebooks-dl-index.tsv"
printf 'someone/else\tElse, Someone/Other\n' >"$ledger"
chmod 444 "$ledger"
if [[ -w "$ledger" ]]; then
  fail "harness: could not make the ledger read-only" \
    "the case has to run as a user the permission bits apply to"
else
  run_sedl -d "$lib"
  assert_exit "a read-only ledger: the run finishes" 0
  assert_contains "the lost entry is warned about" "$STDERR" \
    "aaa/first: could not record Aaa, A/First Book in the ledger"
  assert_file_exists "the book after it still arrives" \
    "$lib/Zzz, Z/Second Book/Second Book.advanced.epub"
  assert_contains "both are reported downloaded" "$STDERR" "downloaded 2 of the 2 attempted"
fi
chmod 644 "$ledger"
