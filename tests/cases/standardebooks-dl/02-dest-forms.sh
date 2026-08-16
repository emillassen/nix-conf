#!/usr/bin/env bash
# -d with a trailing slash. Every library-relative path in this script is made
# by stripping "$dest/" off an absolute one, and with `-d /path/lib/` that
# prefix is "/path/lib//", which matches nothing: the "relative" path comes out
# absolute. rebuild_index then writes absolute paths into the ledger, the next
# run looks for "$dest/$relpath" — a doubly-rooted path that cannot exist —
# decides the whole library is missing, and re-downloads it. Against a cap of
# 100 files per six hours that is days of wall time and a lot of a nonprofit's
# bandwidth.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: -d with a trailing slash, a dot, a relative path"

se_init
se_book milne/now-we-are-six "Milne, A. A." "Now We Are Six"
se_book homer/the-iliad "Homer" "The Iliad"
se_sitemap

# A library that is already complete, and a ledger that has been lost.
run_sedl -d "$SE_LIB"
assert_exit "the seeding run works" 0
rm -f "$SE_LIB/.standardebooks-dl-index.tsv"

ledger="$SE_LIB/.standardebooks-dl-index.tsv"

# --- trailing slash (and two of them) --------------------------------------------
rm -f "$STUBLOG/curl-urls.log"
run_sedl -d "$SE_LIB//"
assert_exit "exits 0" 0
assert_contains "the ledger is rebuilt from the epubs on disk" "$STDERR" \
  "recovered 2 book(s)"
assert_not_contains "with library-relative paths, not absolute ones" \
  "$(cat "$ledger")" "$SE_LIB/"
assert_contains "so the rebuilt ledger points at the right place" \
  "$(cat "$ledger")" "Homer/The Iliad"
assert_contains "and the run finds the library complete" "$STDERR" \
  "all 2 ebooks are already in the library"
assert_eq "nothing was re-downloaded" 1 "$(stub_count curl-urls)"

# --- -d . and -d ./ from inside the library ------------------------------------
for form in . ./; do
  rm -f "$ledger" "$STUBLOG/curl-urls.log"
  RUN_CWD="$SE_LIB" run_sedl -d "$form"
  RUN_CWD=""
  assert_exit "-d $form exits 0" 0
  assert_not_contains "-d $form keeps ledger paths relative" "$(cat "$ledger")" "./"
  assert_contains "-d $form finds the library complete" "$STDERR" \
    "all 2 ebooks are already in the library"
  assert_eq "-d $form downloads nothing" 1 "$(stub_count curl-urls)"
done

# --- a relative path from the parent directory ---------------------------------
rm -f "$ledger" "$STUBLOG/curl-urls.log"
RUN_CWD="$TMP" run_sedl -d library/
RUN_CWD=""
assert_exit "a relative dir with a trailing slash exits 0" 0
assert_not_contains "and still yields relative ledger paths" "$(cat "$ledger")" "library/"
assert_eq "and downloads nothing" 1 "$(stub_count curl-urls)"
