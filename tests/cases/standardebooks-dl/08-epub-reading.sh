#!/usr/bin/env bash
# epub_slug and extract_cover, against every epub shape the library can
# actually contain. Both are what make the ledger recoverable offline and the
# covers free, and both are grep-over-XML, which is exactly the kind of code
# that works on the file you tested it with.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/se.sh"
test_init "standardebooks-dl: reading epubs"

se_init
use_test_path
extract_funcs "$SEDL" "$TMP/epub-funcs.sh" unescape_xml extract_cover epub_slug
# shellcheck source=/dev/null
. "$TMP/epub-funcs.sh"

mk() {
  local out="$TMP/$1"
  shift
  python3 "$TESTS_DIR/lib/mkepub.py" "$out" "$@"
  printf '%s' "$out"
}

check_cover() {
  local label="$1" epub="$2" want="$3" target="$TMP/out-$RANDOM.jpg"
  local rc=0
  extract_cover "$epub" "$target" || rc=1
  if [[ "$want" == ok ]]; then
    assert_eq "$label: succeeds" 0 "$rc"
    assert_file_exists "$label: writes the cover" "$target"
  else
    assert_eq "$label: fails" 1 "$rc"
    assert_file_missing "$label: writes no cover" "$target"
  fi
  assert_file_missing "$label: leaves no .part behind" "$target.part"
}

# --- the ordinary case ------------------------------------------------------------
e="$(mk normal.epub --slug milne/now-we-are-six --title "Now We Are Six")"
assert_eq "the slug is the identifier minus the site prefix" \
  "milne/now-we-are-six" "$(epub_slug "$e")"
check_cover "normal" "$e" ok

# A translator-disambiguated slug keeps all three segments — that is the whole
# point of keying the ledger on it.
e="$(mk translated.epub --slug homer/the-iliad/samuel-butler)"
assert_eq "a three-segment slug survives" "homer/the-iliad/samuel-butler" "$(epub_slug "$e")"

# --- where the OPF sits -------------------------------------------------------------
e="$(mk rootopf.epub --slug a/b --opf-path content.opf)"
assert_eq "an OPF at the zip root still parses" "a/b" "$(epub_slug "$e")"
check_cover "OPF at the zip root" "$e" ok

e="$(mk deepopf.epub --slug a/b --opf-path OEBPS/pkg/content.opf)"
check_cover "OPF two levels down" "$e" ok

# --- how the cover item is spelled ---------------------------------------------------
e="$(mk props-before.epub --slug a/b --properties "svg cover-image")"
check_cover "properties listed before cover-image" "$e" ok
e="$(mk props-after.epub --slug a/b --properties "cover-image svg")"
check_cover "properties listed after cover-image" "$e" ok

e="$(mk entity.epub --slug a/b --cover-href 'images/black&white.jpg' \
  --cover-href-xml 'images/black&amp;white.jpg')"
check_cover "an href carrying an XML entity" "$e" ok

e="$(mk nocover.epub --slug a/b --no-cover-item)"
check_cover "no cover-image item at all" "$e" fail
assert_eq "but the slug still reads" "a/b" "$(epub_slug "$e")"

e="$(mk emptycover.epub --slug a/b --cover-bytes 0)"
check_cover "a zero-byte cover entry" "$e" fail

# --- epubs that are not theirs, or not epubs -------------------------------------------
e="$(mk foreign.epub --no-identifier)"
rc=0
epub_slug "$e" >/dev/null || rc=1
assert_eq "an epub with no Standard Ebooks identifier is rejected" 1 "$rc"
check_cover "a foreign epub can still have its cover read" "$e" ok

e="$(mk broken.epub --corrupt)"
rc=0
epub_slug "$e" >/dev/null 2>&1 || rc=1
assert_eq "a corrupt zip is rejected rather than fatal" 1 "$rc"
check_cover "a corrupt zip" "$e" fail

: >"$TMP/empty.epub"
rc=0
epub_slug "$TMP/empty.epub" >/dev/null 2>&1 || rc=1
assert_eq "a zero-byte file is rejected" 1 "$rc"
check_cover "a zero-byte file" "$TMP/empty.epub" fail

# --- unescape_xml --------------------------------------------------------------------
assert_eq "entities are unescaped, ampersand last" \
  '<a> & "b" '"'"'c'"'"'' \
  "$(unescape_xml '&lt;a&gt; &amp; &quot;b&quot; &apos;c&apos;')"
