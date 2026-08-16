#!/usr/bin/env bash
# The Last/First/Title → "Last, First"/Title migration. It has to happen on
# every ordinary run rather than behind a flag, because the ledger hands stored
# paths straight back to the downloader: without it, a book already synced would
# keep its old directory for ever and only brand new books would land in the
# right place.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: layout migration"

se_init
se_book milne/now-we-are-six "Milne, A. A." "Now We Are Six"
se_book homer/the-iliad "Homer" "The Iliad"
se_book roosevelt/letters "Roosevelt, Theodore, Jr." "Letters"
se_book wells/the-time-machine "Wells, H. G." "The Time Machine"
se_book wells/the-war-of-the-worlds "Wells, H. G." "The War of the Worlds"
se_sitemap

lib="$SE_LIB"
ledger="$lib/.standardebooks-dl-index.tsv"

# A library laid out by the older version, which split the sort name at its
# first ", " and sanitised each half — so "Milne, A. A." became Milne/A. A.
se_touch_book "$lib/Milne/A. A/Now We Are Six" "Now We Are Six"
se_touch_book "$lib/Homer/The Iliad" "The Iliad"                      # mononym: never had a legacy form
se_touch_book "$lib/Roosevelt/Theodore, Jr/Letters" "Letters"         # sort name with its own comma
se_touch_book "$lib/Wells/H. G/The Time Machine" "The Time Machine"
se_touch_book "$lib/Wells/H. G/The War of the Worlds" "The War of the Worlds"
# ... and one of the Wells books has already been migrated by hand, so its
# target is occupied and it must be left alone.
se_touch_book "$lib/Wells, H. G/The War of the Worlds" "The War of the Worlds"

{
  printf 'milne/now-we-are-six\tMilne/A. A/Now We Are Six\n'
  printf 'homer/the-iliad\tHomer/The Iliad\n'
  printf 'roosevelt/letters\tRoosevelt/Theodore, Jr/Letters\n'
} >"$ledger"
cp "$ledger" "$TMP/ledger-before"

# --- -n is a dry run and must not move anything ----------------------------------
run_sedl -d "$lib" -n
assert_exit "-n exits 0" 0
assert_file_exists "-n left the legacy directory alone" "$lib/Milne/A. A/Now We Are Six"
assert_files_identical "-n left the ledger alone" "$TMP/ledger-before" "$ledger"

# --- the real run ------------------------------------------------------------------
run_sedl -d "$lib"
assert_exit "exits 0" 0

assert_file_exists "a plain author is joined back together" \
  "$lib/Milne, A. A/Now We Are Six/Now We Are Six.epub"
assert_file_missing "and the legacy path is gone" "$lib/Milne/A. A"
assert_file_missing "including the now-empty surname level" "$lib/Milne"

assert_file_exists "a mononym is untouched" "$lib/Homer/The Iliad/The Iliad.epub"

assert_file_exists "a sort name carrying its own comma survives the round trip" \
  "$lib/Roosevelt, Theodore, Jr/Letters/Letters.epub"

assert_file_exists "a free book moves" "$lib/Wells, H. G/The Time Machine/The Time Machine.epub"
assert_file_exists "a colliding one stays put" \
  "$lib/Wells/H. G/The War of the Worlds/The War of the Worlds.epub"
assert_contains "and says so, by hand" "$STDERR" "already exists - left in place, merge it by hand"
assert_file_exists "so its author directory is not removed either" "$lib/Wells/H. G"
assert_contains "the summary counts both" "$STDERR" "moved 3 book(s) to Last, First/Title (1 left behind)"

# The ledger has to follow, or every migrated book looks missing and gets
# downloaded again into a freshly recreated legacy directory.
assert_file_contains "the ledger followed" "$ledger" "milne/now-we-are-six	Milne, A. A/Now We Are Six"
assert_file_contains "for the comma case too" "$ledger" "roosevelt/letters	Roosevelt, Theodore, Jr/Letters"
assert_contains "and says how many paths it rewrote" "$STDERR" "2 ledger path(s) updated"

# Nothing was re-downloaded for the books that moved.
assert_not_contains "no legacy directory was recreated" "$(ls -A "$lib")" "Milne"$'\n'
