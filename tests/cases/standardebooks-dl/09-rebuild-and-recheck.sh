#!/usr/bin/env bash
# The ledger is a cache, not state you can lose: every Standard Ebooks epub
# names its own catalog URL, so the whole slug → directory mapping can be
# recovered from the books on disk, offline. -r does that on demand and
# backfills covers at the same time; an ordinary run does it by itself when the
# ledger turns up missing next to a library that is not.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: ledger rebuild and -r"

se_init
se_book milne/now-we-are-six "Milne, A. A." "Now We Are Six"
se_book homer/the-iliad "Homer" "The Iliad"
se_sitemap
lib="$SE_LIB"
ledger="$lib/.standardebooks-dl-index.tsv"

run_sedl -d "$lib"
assert_exit "the seeding run works" 0

# --- -r: offline, and it repairs -------------------------------------------------
rm -f "$ledger" "$lib/Homer/The Iliad/cover.jpg"
printf 'not an image' >"$lib/Milne, A. A/Now We Are Six/cover.jpg"
rm -f "$STUBLOG/curl-urls.log"
run_sedl -d "$lib" -r
assert_exit "-r exits 0" 0
assert_eq "-r asks the site nothing at all" 0 "$(stub_count curl-urls)"
assert_contains "-r reports the covers" "$STDERR" "wrote 2 cover(s) from 2 epub(s) on disk"
assert_file_exists "-r backfills a missing cover" "$lib/Homer/The Iliad/cover.jpg"
assert_not_contains "-r overwrites a damaged one" \
  "$(cat "$lib/Milne, A. A/Now We Are Six/cover.jpg")" "not an image"
assert_contains "-r rebuilds the ledger" "$STDERR" "recovered 2 book(s)"
assert_file_contains "with the right slug" "$ledger" "homer/the-iliad	Homer/The Iliad"

# Idempotent: a second -r adds nothing, because the existing ledger wins
# wherever it already has a slug.
run_sedl -d "$lib" -r
assert_contains "a second -r recovers nothing new" "$STDERR" "recovered 0 book(s)"
assert_eq "and the ledger has not grown" 2 "$(grep -c '' "$ledger")"

# --- an epub that is not one of theirs ---------------------------------------------
mkdir -p "$lib/Someone Else/Their Book"
python3 "$TESTS_DIR/lib/mkepub.py" "$lib/Someone Else/Their Book/Their Book.epub" --no-identifier
run_sedl -d "$lib" -r
assert_contains "a foreign epub is named, not indexed" "$STDERR" \
  "no Standard Ebooks identifier in Their Book.epub"
assert_contains "and counted" "$STDERR" "1 epub(s) carried no identifier"
assert_eq "the ledger still has only the two real books" 2 "$(grep -c '' "$ledger")"
rm -rf "$lib/Someone Else"

# --- the automatic rebuild ------------------------------------------------------------
# A ledger that is missing beside a library that has books in it is a lost
# ledger, not a first run.
rm -f "$ledger" "$STUBLOG/curl-urls.log"
run_sedl -d "$lib"
assert_contains "an ordinary run notices" "$STDERR" "ledger is missing or empty - rebuilding it"
assert_contains "and finds everything already there" "$STDERR" \
  "all 2 ebooks are already in the library"
assert_eq "so it downloads nothing" 1 "$(stub_count curl-urls)"

# --- a truncated file counts as missing -------------------------------------------------
# -s and not -e: a zero-length file is a download that was cut off, and counting
# it as present would leave it that way for ever.
: >"$lib/Homer/The Iliad/The Iliad.azw3"
rm -f "$STUBLOG/curl-urls.log"
run_sedl -d "$lib" -n
assert_contains "-n sees the book as short a format" "$STDOUT" "homer/the-iliad (3/4 formats)"
run_sedl -d "$lib"
assert_contains "and a real run fetches exactly that one file" "$STDERR" \
  "1 files at 100 per 6h00m"
assert_ne "the truncated file is gone" "" "$(cat "$lib/Homer/The Iliad/The Iliad.azw3")"
