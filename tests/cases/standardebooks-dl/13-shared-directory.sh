#!/usr/bin/env bash
# Two catalog entries whose author sort name and title come out the same: two
# translations of one book (Standard Ebooks gives each its own slug, with the
# translator as a third segment, and the same title), or two titles sanitize
# folds together ("A: B" and "A? B" both file as "A- B"). The directory is made
# from the metadata alone, so both used to land in it: the second probe replaced
# the first edition's epub, fetch_one then found the other three formats present
# and kept the first edition's, and both ledger entries pointed at the one
# directory - complete, as far as every later run could tell, and mixed.
#
# Not in the live catalog when this was written (1536 published ebooks, no two
# sharing an author and title slug), which is exactly why it has to be pinned:
# nothing would notice it starting.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: two catalog entries never share a directory"

opf_id() { "$REALBIN/unzip" -p "$1" epub/content.opf | grep -oP '<dc:identifier[^>]*>\K[^<]+'; }

# --- two translations ---------------------------------------------------------
se_init
se_book homer/the-iliad/alexander-pope "Homer" "The Iliad"
se_book homer/the-iliad/william-cowper "Homer" "The Iliad"
se_sitemap
lib="$SE_LIB"
ledger="$lib/.standardebooks-dl-index.tsv"

run_sedl -d "$lib"
assert_exit "exits 0" 0
first="$lib/Homer/The Iliad/The Iliad.epub"
second="$lib/Homer/The Iliad (william-cowper)/The Iliad (william-cowper).epub"
assert_file_exists "the first edition takes the plain name" "$first"
assert_file_exists "the second is set apart by its last slug segment" "$second"
assert_eq "the plain one is still the first edition" \
  "https://standardebooks.org/ebooks/homer/the-iliad/alexander-pope" "$(opf_id "$first")"
assert_eq "and the other is the second" \
  "https://standardebooks.org/ebooks/homer/the-iliad/william-cowper" "$(opf_id "$second")"
assert_file_exists "the second gets all four formats of its own" \
  "$lib/Homer/The Iliad (william-cowper)/The Iliad (william-cowper).advanced.epub"
assert_file_contains "the ledger keeps them apart" "$ledger" \
  "homer/the-iliad/william-cowper	Homer/The Iliad (william-cowper)"
assert_eq "no two ledger entries share a path" "" "$(cut -f2 "$ledger" | sort | uniq -d)"

run_sedl -d "$lib"
assert_contains "a rerun finds both complete" "$STDERR" "all 2 ebooks are already in the library"

# --- the ledger is gone, the directory already holds another edition -----------
# With no ledger entry to say whose directory it is, the epub on disk says so:
# every SE epub names its own catalog URL. Only the second edition is in this
# catalog, so nothing else would claim the directory.
se_init
se_book homer/the-iliad/william-cowper "Homer" "The Iliad"
se_sitemap
lib="$SE_LIB"
python3 "$TESTS_DIR/lib/mkepub.py" "$TMP/pope.epub" \
  --slug homer/the-iliad/alexander-pope --title "The Iliad" --author-fileas "Homer"
mkdir -p "$lib/Homer/The Iliad"
cp "$TMP/pope.epub" "$lib/Homer/The Iliad/The Iliad.epub"
# A ledger that has entries, so the run does not rebuild it from disk first.
printf 'someone/else\tElse, Someone/Other\n' >"$lib/.standardebooks-dl-index.tsv"

run_sedl -d "$lib"
assert_exit "an unledgered edition on disk: exits 0" 0
assert_files_identical "the edition already there is not overwritten" \
  "$TMP/pope.epub" "$lib/Homer/The Iliad/The Iliad.epub"
assert_file_exists "the new one goes beside it" \
  "$lib/Homer/The Iliad (william-cowper)/The Iliad (william-cowper).epub"

# --- an epub that is not one of theirs ----------------------------------------
# Nothing proves it is this book, so it is treated as someone else's.
se_init
se_book homer/the-iliad/william-cowper "Homer" "The Iliad"
se_sitemap
lib="$SE_LIB"
mkdir -p "$lib/Homer/The Iliad"
printf 'my own notes, saved as an epub\n' >"$lib/Homer/The Iliad/The Iliad.epub"
cp "$lib/Homer/The Iliad/The Iliad.epub" "$TMP/mine"
printf 'someone/else\tElse, Someone/Other\n' >"$lib/.standardebooks-dl-index.tsv"

run_sedl -d "$lib"
assert_exit "a foreign epub in the way: exits 0" 0
assert_files_identical "it is left alone" "$TMP/mine" "$lib/Homer/The Iliad/The Iliad.epub"
assert_file_exists "and the book is filed beside it" \
  "$lib/Homer/The Iliad (william-cowper)/The Iliad (william-cowper).epub"

# --- the ledger claims a directory that is gone from disk ----------------------
# Deleted by hand, say, to have it fetched again. The epub test cannot see an
# owner there, but the ledger still can, and has to: if the new edition took
# the plain name, the ledgered one would be refilled into it straight after,
# and the two would be mixed again.
se_init
se_book homer/the-iliad/alexander-pope "Homer" "The Iliad"
se_book homer/the-iliad/william-cowper "Homer" "The Iliad"
se_sitemap
lib="$SE_LIB"
printf 'homer/the-iliad/alexander-pope\tHomer/The Iliad\n' >"$lib/.standardebooks-dl-index.tsv"

run_sedl -d "$lib"
assert_exit "a ledgered directory that is gone: exits 0" 0
assert_eq "the ledgered edition is refilled under its own name" \
  "https://standardebooks.org/ebooks/homer/the-iliad/alexander-pope" "$(opf_id "$first")"
assert_eq "and the new one goes beside it" \
  "https://standardebooks.org/ebooks/homer/the-iliad/william-cowper" "$(opf_id "$second")"
