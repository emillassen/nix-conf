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

# --- -n and the quota ledger ----------------------------------------------------
# The quota ledger is per machine and outside the library, so the library checks
# above cannot see it. -n used to create its directory, touch the file, open the
# lock and rewrite the ledger pruned - writes, from a run that promises none.
se_init
se_book milne/now-we-are-six "Milne, A. A." "Now We Are Six"
se_sitemap
lib="$SE_LIB"
rm -rf "$XDG_STATE_HOME"
run_sedl -d "$lib" -n
assert_exit "-n with no quota state: exits 0" 0
assert_contains "it reports nothing spent" "$STDERR" "quota: 0 downloads in the last 6h00m"
assert_file_missing "and creates no state directory" "$XDG_STATE_HOME"

mkdir -p "$XDG_STATE_HOME/standardebooks-dl"
# Two downloads inside the window and one long aged out, which a real run prunes.
{
  printf '%s\n' "$(($(now) - 30000))"
  printf '%s\n' "$(($(now) - 600))"
  printf '%s\n' "$(($(now) - 60))"
} >"$(quota_ledger)"
cp "$(quota_ledger)" "$TMP/quota-before"
run_sedl -d "$lib" -n
assert_contains "-n counts only what is inside the window" "$STDERR" \
  "quota: 2 downloads in the last 6h00m"
assert_files_identical "and leaves the ledger byte for byte, expired entry and all" \
  "$TMP/quota-before" "$(quota_ledger)"
assert_file_missing "without leaving a lock file behind" "$XDG_STATE_HOME/standardebooks-dl/lock"

# --- -n beside a library that has lost its ledger --------------------------------
# A real run rebuilds a lost ledger from the epubs before it looks at anything,
# so the dry run has to recover the same mapping - in memory - or it reports a
# complete library as entirely missing and four files a book to fetch, which is
# weeks of a job that would in fact do nothing.
run_sedl -d "$lib"
assert_exit "seeding a complete library" 0
rm -f "$lib/.standardebooks-dl-index.tsv"
run_sedl -d "$lib" -n
assert_exit "-n without a ledger: exits 0" 0
assert_eq "nothing is listed" "" "$STDOUT"
assert_contains "nothing is missing" "$STDERR" "0 of 1 ebooks not in the library yet"
assert_contains "and nothing to fetch" "$STDERR" "0 files to fetch"
assert_file_missing "the ledger is still not written" "$lib/.standardebooks-dl-index.tsv"
