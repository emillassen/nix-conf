#!/usr/bin/env bash
# A first sync against an empty library: the catalog comes out of the sitemap in
# one request, only published books count, each book lands under its epub's own
# sort name, the cover is lifted out of the epub, and the ledger records where
# everything went.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: first sync"

se_init
se_book milne/now-we-are-six "Milne, A. A." "Now We Are Six"
se_book homer/the-iliad/samuel-butler "Homer" "The Iliad"
# An ampersand in the title. It reaches the script XML-escaped, as it is written
# in the OPF, and has to be unescaped before it becomes a directory name.
se_book stevenson/jekyll-and-hyde "Stevenson, Robert Louis" "Dr. Jekyll &amp; Mr. Hyde"
se_placeholder someone/a-book-still-in-copyright
se_sitemap

run_sedl -d "$SE_LIB"

assert_exit "exits 0" 0
assert_contains "counts only the published books" "$STDERR" "3 published ebooks in the catalog"
assert_contains "reports the job up front" "$STDERR" "0 of 3 already complete - 3 to fetch"
assert_contains "and prices it in files, not books" "$STDERR" "12 files at 100 per 6h00m"

# file-as becomes the author directory: one level, not "Milne/A. A.", and not
# the display name. The trailing dot goes, because Windows and SMB reject a path
# component that ends in one — so the directory is "Milne, A. A", one character
# short of what Calibre's {author_sort} prints. Nearly every author whose sort
# name ends in an initial is affected, which is why it is pinned here.
for ext in .epub .azw3 .kepub.epub .advanced.epub; do
  assert_file_exists "Now We Are Six$ext" "$SE_LIB/Milne, A. A/Now We Are Six/Now We Are Six$ext"
done
assert_file_exists "the cover was lifted out of the epub" \
  "$SE_LIB/Milne, A. A/Now We Are Six/cover.jpg"
assert_file_exists "a mononym author gets one directory level" \
  "$SE_LIB/Homer/The Iliad/The Iliad.epub"
assert_file_exists "an ampersand in a title is unescaped, not left as &amp;" \
  "$SE_LIB/Stevenson, Robert Louis/Dr. Jekyll & Mr. Hyde/Dr. Jekyll & Mr. Hyde.epub"

assert_file_contains "the ledger records the slug and its path" \
  "$SE_LIB/.standardebooks-dl-index.tsv" "milne/now-we-are-six	Milne, A. A/Now We Are Six"
assert_file_contains "including the translator segment" \
  "$SE_LIB/.standardebooks-dl-index.tsv" "homer/the-iliad/samuel-butler	Homer/The Iliad"

assert_contains "progress is a position, not a running total" "$STDOUT" "[1/3] downloaded:"
assert_contains "and reports what is left" "$STDOUT" "2 left, ~"
assert_contains "the summary counts the covers" "$STDERR" "wrote 3 new cover image(s)"
assert_contains "no warnings" "$STDERR" "no warnings"

# Every download counted against the ledger, and nothing else did: the sitemap
# is not rate-limited and must not be recorded.
assert_eq "twelve downloads recorded in the quota ledger" 12 \
  "$(grep -c '' "$(quota_ledger)")"

# A second run has nothing to do and asks the site exactly one question.
rm -f "$STUBLOG/curl-urls.log"
run_sedl -d "$SE_LIB"
assert_exit "the rerun exits 0" 0
assert_contains "and finds the library complete" "$STDERR" \
  "all 3 ebooks are already in the library - nothing to do"
assert_eq "at the cost of one request, the sitemap" 1 "$(stub_count curl-urls)"
