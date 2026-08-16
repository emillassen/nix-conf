#!/usr/bin/env bash
# -n's two lists and its arithmetic, and the sitemap filter that decides what
# the catalog even is. Both matter out of proportion to their size: the filter
# is the difference between 1483 books and ~4000 URLs two thirds of which have
# no files, and -n is the only thing anyone reads before committing to a job
# measured in days.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: -n and the catalog filter"

se_init
se_book milne/now-we-are-six "Milne, A. A." "Now We Are Six"
se_book homer/the-iliad/samuel-butler "Homer" "The Iliad"
se_book carroll/alice "Carroll, Lewis" "Alice in Wonderland"
se_placeholder someone/still-in-copyright
se_placeholder another/also-years-away
se_sitemap
lib="$SE_LIB"

# --- an empty library -----------------------------------------------------------
run_sedl -d "$lib" -n
assert_exit "-n exits 0" 0
assert_contains "placeholders are not in the catalog" "$STDERR" \
  "3 published ebooks in the catalog"
assert_not_contains "nor is the placeholder listed as missing" "$STDOUT" "still-in-copyright"
assert_not_contains "nor the author page" "$STDOUT" "jane-austen"
assert_contains "the translator segment survives the filter" "$STDOUT" \
  "homer/the-iliad/samuel-butler"
assert_contains "everything is missing" "$STDERR" "3 of 3 ebooks not in the library yet"
assert_contains "four files per book" "$STDERR" "12 files to fetch"
assert_contains "and an estimate against the site's own limit" "$STDERR" \
  "at the site's limit of 100 per 6h00m that is about 43m"
assert_contains "with what has been spent already" "$STDERR" \
  "quota: 0 downloads in the last 6h00m"

# -n is a dry run: no ledger, no library directory conjured up, nothing fetched.
assert_file_missing "-n writes no ledger" "$lib/.standardebooks-dl-index.tsv"
assert_eq "-n fetches only the sitemap" 1 "$(stub_count curl-urls)"
run_sedl -d "$TMP/does-not-exist" -n
assert_file_missing "-n does not create the library directory either" "$TMP/does-not-exist"

# --- a partially complete library ----------------------------------------------
run_sedl -d "$lib"
assert_exit "the seeding run works" 0
rm -f "$lib/Carroll, Lewis/Alice in Wonderland/Alice in Wonderland.azw3"
: >"$lib/Carroll, Lewis/Alice in Wonderland/Alice in Wonderland.kepub.epub"
rm -rf "$lib/Homer"
# The ledger still points at the deleted book, so it counts as "in the library
# but missing formats" — nothing on disk, but a known home for it.
run_sedl -d "$lib" -n
assert_exit "-n exits 0" 0
assert_contains "a book short two formats is annotated" "$STDOUT" \
  "carroll/alice (2/4 formats)"
assert_contains "a zero-byte file counts as missing" "$STDOUT" "carroll/alice (2/4 formats)"
assert_contains "a book whose directory went away is in the same list" "$STDOUT" \
  "homer/the-iliad/samuel-butler (0/4 formats)"
assert_contains "nothing is missing entirely any more" "$STDERR" \
  "0 of 3 ebooks not in the library yet"
assert_contains "two are short some formats" "$STDERR" \
  "2 more are in the library but missing formats"
assert_contains "counted per file, not per book" "$STDERR" "6 files to fetch"
