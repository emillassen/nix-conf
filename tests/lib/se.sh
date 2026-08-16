# shellcheck shell=bash
# Helpers for the standardebooks-dl cases: a fake standardebooks.org (its
# sitemap and its four download URLs per book), a library directory, and the
# per-machine quota ledger the script keeps outside the library.
#
# Nothing here ever reaches the real site. That matters more than usual: their
# limiter is 100 downloads per six hours per IP, and a hidden /honeypot link in
# their page header is wired to fail2ban with maxretry = 1, bantime = 24h.

SE_LIB=""
SE_SITE=""
SE_SITEMAP=""

se_init() {
  require_tool unzip python3
  use_stubs curl date sleep
  SE_LIB="$TMP/library"
  SE_SITE="$TMP/site"
  SE_SITEMAP="$SE_SITE/sitemap.xml"
  mkdir -p "$SE_LIB" "$SE_SITE"
  export CURL_MAP="$TMP/curl-map"
  : >"$CURL_MAP"
  # The ledger is per machine, not per library, and lives under XDG_STATE_HOME.
  export XDG_STATE_HOME="$TMP/state"
  mkdir -p "$XDG_STATE_HOME"
  export FAKE_CLOCK="$TMP/clock"
  printf '%s' "${1:-1800000000}" >"$FAKE_CLOCK"
  SE_SLUGS=()
  SE_PLACEHOLDERS=()
}

now() { cat "$FAKE_CLOCK"; }
set_now() { printf '%s' "$1" >"$FAKE_CLOCK"; }
quota_ledger() { printf '%s/standardebooks-dl/download-quota' "$XDG_STATE_HOME"; }

# A published book: it gets a /text page in the sitemap and four downloadable
# files. The .epub is a real zip, because the script reads its OPF for the
# author's sort name and lifts the cover out of it.
se_book() {
  local slug="$1" fileas="$2" title="$3"
  shift 3
  local dl="${slug//\//_}" ext
  local epub="$SE_SITE/$dl.epub"
  python3 "$TESTS_DIR/lib/mkepub.py" "$epub" \
    --slug "$slug" --title "$title" --author-fileas "$fileas" "$@"
  printf 'https://standardebooks.org/ebooks/%s/downloads/%s.epub?*\t200\t@%s\n' \
    "$slug" "$dl" "$epub" >>"$CURL_MAP"
  for ext in .azw3 .kepub.epub _advanced.epub; do
    printf 'other format\n' >"$SE_SITE/$dl$ext"
    printf 'https://standardebooks.org/ebooks/%s/downloads/%s%s?*\t200\t@%s\n' \
      "$slug" "$dl" "$ext" "$SE_SITE/$dl$ext" >>"$CURL_MAP"
  done
  SE_SLUGS+=("$slug")
}

# A title announced years ahead of its U.S. public-domain date: it is in the
# sitemap but has no /text subpage and no files. Two thirds of the sitemap looks
# like this, which is the whole reason the /text filter exists.
se_placeholder() { SE_PLACEHOLDERS+=("$1"); }

# An author page, which must not be mistaken for a book.
se_sitemap() {
  local slug
  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<urlset>\n'
    printf '  <url><loc>https://standardebooks.org/ebooks</loc></url>\n'
    for slug in ${SE_SLUGS[@]+"${SE_SLUGS[@]}"}; do
      printf '  <url><loc>https://standardebooks.org/ebooks/%s</loc></url>\n' "$slug"
      printf '  <url><loc>https://standardebooks.org/ebooks/%s/text</loc></url>\n' "$slug"
    done
    for slug in ${SE_PLACEHOLDERS[@]+"${SE_PLACEHOLDERS[@]}"}; do
      printf '  <url><loc>https://standardebooks.org/ebooks/%s</loc></url>\n' "$slug"
    done
    # An author page that has somehow acquired a /text suffix: one segment, so
    # the final `grep /` must drop it.
    printf '  <url><loc>https://standardebooks.org/ebooks/jane-austen/text</loc></url>\n'
    printf '</urlset>\n'
  } >"$SE_SITEMAP"
  printf 'https://standardebooks.org/sitemap\t200\t@%s\n' "$SE_SITEMAP" >>"$CURL_MAP"
}

run_sedl() { run_fragment "$SEDL" "$@"; }

# The four files a complete book has on disk.
se_touch_book() {
  local dir="$1" base="$2" ext
  mkdir -p "$dir"
  for ext in .epub .azw3 .kepub.epub .advanced.epub; do
    printf 'content\n' >"$dir/$base$ext"
  done
}
