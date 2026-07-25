usage() {
  # requested help goes to stdout; usage errors go to stderr
  [[ "${1:-0}" == 0 ]] || exec >&2
  cat <<'EOF'
Usage: standardebooks-dl [-d DIR] [-n] [-r] [-h]

Download every ebook from standardebooks.org that isn't already in DIR yet,
laid out the way Calibre-style libraries expect:

  Author Last Name/Author First Name/Book Title/Book Title.epub
  Author Last Name/Author First Name/Book Title/Book Title.azw3
  Author Last Name/Author First Name/Book Title/Book Title.kepub.epub
  Author Last Name/Author First Name/Book Title/Book Title.advanced.epub

The full catalog (a few thousand ebooks, spanning the site's 100+ listing
pages) is discovered in one request via the site's sitemap, instead of
crawling /ebooks page by page. Author name and title come from each ebook's
own epub metadata (its file-as sort name), not guessed from the display
name, so multi-word surnames and particles (von, de, van Gogh, ...) come out
right.

Each book's embedded cover is lifted out of its epub as a cover.jpg next to
the files, so KDE's Dolphin shows a folder thumbnail and Calibre / Jellyfin
pick the artwork up without opening the epub. This costs no extra request -
the cover is read straight from the epub already downloaded.

A ledger at DIR/.standardebooks-dl-index.tsv records which ebooks are fully
downloaded, so reruns only fetch what's new since last time - safe to run
regularly or interrupt and resume. Books whose 4 files already exist but
fell out of the ledger are re-indexed instead of re-downloaded; books in the
ledger whose files went missing (e.g. deleted by hand) have just those
formats re-fetched.

Options:
  -d DIR   library root (default: current directory)
  -n       don't download; list ebooks not yet in the library, one per line
  -r       don't download; (re)generate cover.jpg for every book already on
           disk, straight from the local epubs - no network. Use it to
           backfill covers for a library built before covers existed, or to
           repair them (existing covers are overwritten)
  -h       show this help

A first run against an empty library downloads the entire catalog - several
thousand books at up to 4 files each - so it deliberately paces every single
request (several seconds apart, growing further if the site starts answering
429 Too Many Requests) rather than hammering the site; expect it to take
hours, and expect it to slow down further, not speed up, if it hits a rate
limit. Standard Ebooks lists some translations ahead of their U.S. public-
domain release date; these have no files yet and are skipped with a note
rather than treated as failures.
EOF
  exit "${1:-0}"
}

dest="."
list_only=0
recheck=0
while getopts ":d:nrh" opt; do
  case "$opt" in
    d) dest="$OPTARG" ;;
    n) list_only=1 ;;
    r) recheck=1 ;;
    h) usage ;;
    :)
      echo "standardebooks-dl: option -$OPTARG requires an argument" >&2
      usage 1
      ;;
    *)
      echo "standardebooks-dl: unknown option -$OPTARG" >&2
      usage 1
      ;;
  esac
done
shift $((OPTIND - 1))
if [[ $# -gt 0 ]]; then
  echo "standardebooks-dl: unexpected argument: $1" >&2
  usage 1
fi
if [[ $((list_only + recheck)) -gt 1 ]]; then
  echo "standardebooks-dl: -n and -r cannot be combined" >&2
  exit 1
fi

base_url="https://standardebooks.org"
ua="standardebooks-dl (personal library sync script)"

mkdir -p "$dest"

warnings=()
warn() {
  echo "standardebooks-dl: warning: $*" >&2
  warnings+=("$*")
}

# Windows/SMB-illegal characters are replaced, not stripped, so two titles
# that only differ by one of these don't collide on disk; trailing dots and
# spaces are trimmed since Windows/SMB reject those too. Keeping paths safe
# for non-Linux filesystems matters here since a library like this commonly
# ends up served from a NAS share.
sanitize() {
  printf '%s' "$1" | sed -E 's#[\\/:*?"<>|]#-#g; s/[[:space:].]+$//'
}

unescape_xml() {
  local s="$1"
  s="${s//&lt;/<}"
  s="${s//&gt;/>}"
  s="${s//&quot;/\"}"
  s="${s//&apos;/\'}"
  s="${s//&amp;/&}"
  printf '%s' "$s"
}

# Standard Ebooks embeds a JPEG cover in every epub; lift it out next to the
# book files as cover.jpg so KDE's Dolphin shows a folder thumbnail and
# Calibre / Jellyfin / Calibre-Web get artwork without cracking the epub open.
# The cover's location is read from the epub's own manifest (the item flagged
# properties="cover-image"), not hardcoded, so an unusual layout still
# resolves. No network request - it reads the epub already on disk. Returns 0
# on success, non-zero if the epub can't be parsed (the caller warns). Always
# called as an `if` condition, so its own failures never trip the run's set -e.
extract_cover() {
  local epub="$1" target="$2" opf_path opf href opf_dir coverzip
  [[ -e "$epub" ]] || return 1
  # grep may find nothing (odd epub) and `head` closes the pipe early; with
  # pipefail either makes the assignment "fail", so `|| true` and an emptiness
  # check stand in for it instead of aborting.
  opf_path="$(unzip -p "$epub" META-INF/container.xml 2>/dev/null |
    grep -oP 'full-path="\K[^"]+' | head -n1)" || true
  [[ -n "$opf_path" ]] || return 1
  opf="$(unzip -p "$epub" "$opf_path" 2>/dev/null)" || true
  [[ -n "$opf" ]] || return 1
  # the cover-image item can list several space-separated properties in any
  # order, so match the whole <item> tag carrying it, then read its href back
  href="$(grep -oP '<item\b[^>]*\bproperties="[^"]*cover-image[^"]*"[^>]*>' <<<"$opf" |
    grep -oP '\bhref="\K[^"]+' | head -n1)" || true
  [[ -n "$href" ]] || return 1
  href="$(unescape_xml "$href")"
  # the href is relative to the folder the opf itself sits in inside the zip
  opf_dir="${opf_path%/*}"
  [[ "$opf_dir" == "$opf_path" ]] && opf_dir=""
  coverzip="${opf_dir:+$opf_dir/}$href"
  unzip -p "$epub" "$coverzip" >"$target.part" 2>/dev/null || {
    rm -f "$target.part"
    return 1
  }
  [[ -s "$target.part" ]] || {
    rm -f "$target.part"
    return 1
  }
  mv -- "$target.part" "$target" || {
    rm -f "$target.part"
    return 1
  }
}

media_exists() {
  local dir="$1" base="$2"
  [[ -e "$dir/$base.epub" && -e "$dir/$base.azw3" && -e "$dir/$base.kepub.epub" && -e "$dir/$base.advanced.epub" ]]
}

# -r: (re)generate cover.jpg for every book already on disk, read straight from
# the local epubs. No catalog fetch, no network, no pacing - it only touches
# files already downloaded, overwriting existing covers so it doubles as a
# repair. The compatible .epub (not the .kepub.epub / .advanced.epub variants)
# is the one whose cover we read.
if [[ "$recheck" == 1 ]]; then
  covers=0
  cover_failed=0
  scanned=0
  while IFS= read -r -d '' epub; do
    scanned=$((scanned + 1))
    dir="${epub%/*}"
    if extract_cover "$epub" "$dir/cover.jpg"; then
      covers=$((covers + 1))
    else
      warn "${dir#"$dest"/}: no readable cover in ${epub##*/}"
      cover_failed=$((cover_failed + 1))
    fi
  done < <(find "$dest" -type f -name '*.epub' \
    ! -name '*.kepub.epub' ! -name '*.advanced.epub' -print0)
  echo >&2
  echo "standardebooks-dl: ---- cover backfill ----" >&2
  echo "standardebooks-dl: wrote $covers cover(s) from $scanned epub(s) on disk" >&2
  if [[ "$cover_failed" -gt 0 ]]; then
    echo "standardebooks-dl: $cover_failed epub(s) had no readable cover:" >&2
    for w in "${warnings[@]}"; do
      echo "standardebooks-dl:   warning: $w" >&2
    done
  fi
  exit 0
fi

index_file="$dest/.standardebooks-dl-index.tsv"
touch "$index_file"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# One request enumerates every ebook on the site, sparing the 100+ requests a
# page-by-page crawl of /ebooks?page=N would need. Each book's own page
# appears in the sitemap alongside its /text, /text/single-page, /downloads
# and /feeds subpages - strip those known non-book suffixes to keep just the
# canonical book URLs. Books with more than one translator are disambiguated
# with a 3rd path segment (/ebooks/author/book/translator), so "has a slash"
# (not a fixed segment count) is what distinguishes a book from an author page.
echo "standardebooks-dl: fetching catalog..." >&2
sitemap="$tmpdir/sitemap.xml"
if ! curl -fsSL -A "$ua" --connect-timeout 15 --max-time 60 -o "$sitemap" "$base_url/sitemap"; then
  echo "standardebooks-dl: could not fetch $base_url/sitemap" >&2
  exit 1
fi
mapfile -t books < <(
  grep -oP '(?<=<loc>)https://standardebooks\.org/ebooks/[^<]+(?=</loc>)' "$sitemap" |
    sed -E 's#^https://standardebooks\.org/ebooks/##' |
    grep -vE '/(text|text/single-page|downloads|feeds)$' |
    grep '/' |
    sort -u
)
if [[ ${#books[@]} -eq 0 ]]; then
  echo "standardebooks-dl: sitemap yielded no ebooks - site layout may have changed" >&2
  exit 1
fi
echo "standardebooks-dl: ${#books[@]} ebooks in the catalog" >&2

declare -A indexed_path
while IFS=$'\t' read -r slug relpath; do
  [[ -n "$slug" ]] && indexed_path["$slug"]="$relpath"
done <"$index_file"

# Standard Ebooks' own download links, in the order offered on an ebook's
# page; index 0 (plain .epub) doubles as the probe used to learn the book's
# metadata below, so it's usually already in place by the time this runs.
url_exts=(".epub" ".azw3" ".kepub.epub" "_advanced.epub")
local_exts=(".epub" ".azw3" ".kepub.epub" ".advanced.epub")

# Every single request is paced at least this many seconds apart; hitting a
# 429 doubles it (capped) for the rest of the run and never comes back down -
# one rate-limit response means we were already going too fast, so the fix
# is to slow the whole run down, not just the request that got throttled.
# The starting pace is deliberately conservative: the site's rate-limit window
# is long, so a run that only slows down *after* the first 429 has already
# tripped it and has to sit out the penalty; starting slow avoids the trip.
pace=8
max_pace=120
throttle() { sleep "$pace"; }

# Fetches $1 into $2. Both --connect-timeout and --max-time are set because a
# server that throttles by stalling the connection instead of answering 429
# would otherwise hang curl forever - that's what happened before this was
# added. Retries on 429 with growing backoff, up to 5 times, before giving up
# for this run. Returns 0 ok, 2 not found (404), 1 any other failure
# (network error, or 429 that didn't clear after retrying).
fetch_url() {
  local url="$1" out="$2" attempt=0 code
  while :; do
    if ! code="$(curl -s -o "$out" -w '%{http_code}' \
      --connect-timeout 15 --max-time 180 -A "$ua" -L "$url")"; then
      return 1
    fi
    case "$code" in
      200) return 0 ;;
      404) return 2 ;;
      429)
        attempt=$((attempt + 1))
        pace=$((pace * 2))
        [[ "$pace" -gt "$max_pace" ]] && pace="$max_pace"
        if [[ "$attempt" -ge 5 ]]; then
          return 1
        fi
        echo "standardebooks-dl: rate-limited (429) - backing off to ${pace}s between requests" >&2
        sleep "$pace"
        ;;
      *)
        return 1
        ;;
    esac
  done
}

fetch_one() {
  local dlbase="$1" titledir="$2" base="$3" url_ext="$4" local_ext="$5" target rc
  target="$titledir/$base$local_ext"
  [[ -e "$target" ]] && return 0
  # `|| rc=$?`, not a bare call then `rc=$?`: writeShellApplication runs
  # under set -e, and a plain non-zero-returning statement (even one whose
  # status is read on the next line) aborts the whole script right there -
  # every ordinary 404 would have silently killed the run before this fix.
  rc=0
  fetch_url "$dlbase$url_ext?source=download" "$target.part" || rc=$?
  throttle
  if [[ "$rc" == 0 ]]; then
    mv -- "$target.part" "$target"
    return 0
  fi
  rm -f "$target.part"
  warn "failed to fetch $dlbase$url_ext"
  return 1
}

total=${#books[@]}
already=0
downloaded=0
covers=0
unavailable=0
failed=0
missing_list=()

for slug in "${books[@]}"; do
  relpath="${indexed_path[$slug]:-}"

  if [[ -n "$relpath" ]] && media_exists "$dest/$relpath" "${relpath##*/}"; then
    already=$((already + 1))
    continue
  fi

  if [[ "$list_only" == 1 ]]; then
    [[ -z "$relpath" ]] && missing_list+=("$slug")
    continue
  fi

  dlbase="$base_url/ebooks/$slug/downloads/${slug//\//_}"

  if [[ -z "$relpath" ]]; then
    # Not in the ledger: probe with the compatible epub first. A 404 here
    # means the title is listed ahead of its U.S. public-domain release date
    # and has no files yet - not a failure, just not downloadable yet. Any
    # other error is a real failure and is retried on the next run.
    epub_tmp="$tmpdir/probe.epub"
    rm -f "$epub_tmp"
    rc=0
    fetch_url "$dlbase.epub?source=download" "$epub_tmp" || rc=$?
    throttle
    if [[ "$rc" != 0 ]]; then
      if [[ "$rc" == 2 ]]; then
        unavailable=$((unavailable + 1))
      else
        warn "$slug: failed to fetch compatible epub"
        failed=$((failed + 1))
      fi
      continue
    fi

    # Each of these is a grep that may legitimately find nothing (an
    # unexpected epub layout, odd metadata) - with pipefail active, that
    # makes the assignment itself "fail", which as a bare statement would
    # trip set -e same as the fetch_url calls above. `|| true` keeps such a
    # book handled by the empty-value check below instead of aborting the run.
    opf_path="$(unzip -p "$epub_tmp" META-INF/container.xml 2>/dev/null | grep -oP 'full-path="\K[^"]+')" || true
    opf="$([[ -n "$opf_path" ]] && unzip -p "$epub_tmp" "$opf_path" 2>/dev/null || true)"
    author_fileas="$(grep -oP '<meta property="file-as" refines="#author[^"]*">\K[^<]+' <<<"$opf" | head -n1)" || true
    title="$(grep -oP '<dc:title id="title">\K[^<]+' <<<"$opf" | head -n1)" || true
    if [[ -z "$author_fileas" || -z "$title" ]]; then
      warn "$slug: could not read author/title from content.opf"
      failed=$((failed + 1))
      continue
    fi
    author_fileas="$(unescape_xml "$author_fileas")"
    title="$(unescape_xml "$title")"

    # file-as is "Last, First" for named authors; mononyms (Aesop, Homer,
    # Anonymous...) carry no comma and get just one directory level.
    author_last="$(sanitize "${author_fileas%%, *}")"
    author_first=""
    [[ "$author_fileas" == *", "* ]] && author_first="$(sanitize "${author_fileas#*, }")"
    base="$(sanitize "$title")"

    if [[ -n "$author_first" ]]; then
      titledir="$dest/$author_last/$author_first/$base"
    else
      titledir="$dest/$author_last/$base"
    fi
    mkdir -p "$titledir"
    mv -- "$epub_tmp" "$titledir/$base.epub"
    relpath="${titledir#"$dest"/}"
    printf '%s\t%s\n' "$slug" "$relpath" >>"$index_file"
    indexed_path["$slug"]="$relpath"
  fi

  titledir="$dest/$relpath"
  base="${relpath##*/}"
  mkdir -p "$titledir"

  ok=1
  for i in "${!url_exts[@]}"; do
    fetch_one "$dlbase" "$titledir" "$base" "${url_exts[$i]}" "${local_exts[$i]}" || ok=0
  done

  # With the epub on disk, lift its embedded cover out as cover.jpg (local, no
  # request), but only when one isn't already there - a normal run never
  # rewrites an existing cover; use -r to refresh them across the library.
  if [[ -e "$titledir/$base.epub" && ! -e "$titledir/cover.jpg" ]]; then
    if extract_cover "$titledir/$base.epub" "$titledir/cover.jpg"; then
      covers=$((covers + 1))
    else
      warn "$relpath: could not extract cover from epub"
    fi
  fi

  if [[ "$ok" == 1 ]]; then
    downloaded=$((downloaded + 1))
    echo "standardebooks-dl: downloaded ($downloaded new so far): $relpath"
  else
    failed=$((failed + 1))
  fi
done

if [[ "$list_only" == 1 ]]; then
  if [[ ${#missing_list[@]} -gt 0 ]]; then
    printf '%s\n' "${missing_list[@]}"
  fi
  echo "standardebooks-dl: ${#missing_list[@]} of $total ebooks not in the library yet" >&2
  exit 0
fi

echo >&2
echo "standardebooks-dl: ---- run summary ----" >&2
echo "standardebooks-dl: $already of $total ebooks were already in the library" >&2
echo "standardebooks-dl: downloaded $downloaded new ebook(s)" >&2
if [[ "$covers" -gt 0 ]]; then
  echo "standardebooks-dl: wrote $covers new cover image(s)" >&2
fi
if [[ "$unavailable" -gt 0 ]]; then
  echo "standardebooks-dl: $unavailable ebook(s) skipped - not yet released (ahead of their public-domain date)" >&2
fi
if [[ ${#warnings[@]} -gt 0 ]]; then
  if [[ "$failed" -gt 0 ]]; then
    echo "standardebooks-dl: $failed ebook(s) failed - rerun to retry" >&2
  fi
  echo "standardebooks-dl: warnings:" >&2
  for w in "${warnings[@]}"; do
    echo "standardebooks-dl:   warning: $w" >&2
  done
else
  echo "standardebooks-dl: no warnings" >&2
fi
