usage() {
  # requested help goes to stdout; usage errors go to stderr
  [[ "${1:-0}" == 0 ]] || exec >&2
  cat <<'EOF'
Usage: standardebooks-dl [-d DIR] [-n] [-r] [-h]

Download every ebook from standardebooks.org that isn't already in DIR yet,
laid out the way Calibre-style libraries expect:

  Last Name, First Name/Book Title/Book Title.epub
  Last Name, First Name/Book Title/Book Title.azw3
  Last Name, First Name/Book Title/Book Title.kepub.epub
  Last Name, First Name/Book Title/Book Title.advanced.epub

The full catalog (some 1500 ebooks, spanning the site's 30-odd listing pages)
is discovered in one request via the site's sitemap, instead of crawling
/ebooks page by page. Only ebooks that are actually published are picked up:
the sitemap also lists titles announced years ahead of their U.S. public-
domain date, which outnumber the real catalog roughly two to one and have no
files to download, so they are filtered out rather than probed on every run.

Author name and title come from each ebook's own epub metadata (its file-as
sort name), not guessed from the display name, so multi-word surnames and
particles (von, de, van Gogh, ...) come out right. That sort name is the
author directory verbatim - the same
"Last, First" form Calibre's {author_sort} template produces (Milne, A. A.),
and a plain mononym (Aesop, Homer, Anonymous, ...) where there is no first
name. A library laid out by an older version, which split that name into
Last/First/ directories, is moved over to it automatically on the next run
(-n excepted, being a dry run); no re-downloading involved.

Each book's embedded cover is lifted out of its epub as a cover.jpg next to
the files, so KDE's Dolphin shows a folder thumbnail and Calibre / Jellyfin
pick the artwork up without opening the epub. This costs no extra request -
the cover is read straight from the epub already downloaded.

A ledger at DIR/.standardebooks-dl-index.tsv records which ebooks are fully
downloaded, so reruns only fetch what's new since last time - safe to run
regularly or interrupt and resume. It is a cache rather than state you can
lose: every Standard Ebooks epub carries its own catalog URL in its
metadata, so the ledger is rebuilt from the books already on disk - no
requests, no re-downloading - whenever it turns up missing or empty, and by
-r on demand. Books in the ledger whose files went missing (e.g. deleted by
hand) have just those formats re-fetched; a file that is present but empty
counts as missing, so a truncated download is replaced rather than kept
forever.

Options:
  -d DIR   library root (default: current directory)
  -n       don't download; list what a run would fetch, one per line: first
           the ebooks missing from the library entirely, then the ones on
           disk missing some of their 4 formats (annotated with how many of
           them are there)
  -r       don't download; (re)generate cover.jpg for every book already on
           disk and rebuild the ledger from those same epubs - both read
           straight from local files, no network. Use it to backfill covers
           for a library built before covers existed, to repair them
           (existing covers are overwritten), or to rebuild a ledger that
           was lost or damaged
  -h       show this help

Standard Ebooks caps ebook downloads at 100 files per 6 hours per IP address
(and 35 per 30 seconds), answering 429 beyond that. Nothing gets round it, so
that cap alone decides how long a sync takes: 4 files a book works out at
roughly 25 books every 6 hours, and a first run against an empty library -
some 1500 books, about 6000 files - therefore takes on the order of two weeks
of wall time. Only downloads are limited; checking what is already in the
library needs no requests at all, so a library that is up to date finishes in
one request, the sitemap, and no waiting.

Rather than guess at a delay, the run keeps a ledger of the downloads the site
has served it, in

  ${XDG_STATE_HOME:-~/.local/state}/standardebooks-dl/download-quota

and waits exactly as long as that says it must - never longer, and never so
briefly that it trips the limit. Because the ledger is on disk and not in the
process, this survives being interrupted: stopping the run and starting it
again a minute later will not spend a budget that is already spent. It records
this machine rather than this library, since the cap is per IP address.

A run works out the whole job up front and then reports one line per book, so
it can be left alone and checked in on:

  standardebooks-dl: 3 of 1483 already complete - 1480 to fetch
  standardebooks-dl: 5920 files at 100 per 6h00m (the site's limit) - about 14d18h; 0 of 100 spent already
  standardebooks-dl: [1/1480] downloaded: Milne, A. A./Now We Are Six - 1479 left, ~14d17h

The per-book time is elapsed-so-far per book extrapolated over what is left;
it settles as the run goes. Waits for the six-hour window to drain are
announced when they start, so a run sitting quietly for five hours is not
mistaken for a hung one.
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
  [[ -s "$epub" ]] || return 1
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

# Every Standard Ebooks epub names its own catalog URL as the package's unique
# identifier - including the translator segment that disambiguates a book with
# several translations - which is exactly the slug the ledger is keyed by. So
# the mapping from catalog entry to directory on disk can always be recovered
# from the books themselves, without asking the site anything. Prints the slug;
# returns non-zero for an epub that isn't one of theirs (or won't parse).
epub_slug() {
  local epub="$1" opf_path opf id
  [[ -s "$epub" ]] || return 1
  # same `|| true` dance as extract_cover: under pipefail a grep that matches
  # nothing would otherwise abort the whole run instead of failing this one book
  opf_path="$(unzip -p "$epub" META-INF/container.xml 2>/dev/null |
    grep -oP 'full-path="\K[^"]+' | head -n1)" || true
  [[ -n "$opf_path" ]] || return 1
  opf="$(unzip -p "$epub" "$opf_path" 2>/dev/null)" || true
  [[ -n "$opf" ]] || return 1
  id="$(grep -oP '<dc:identifier[^>]*>\Khttps://standardebooks\.org/ebooks/[^<]+' <<<"$opf" |
    head -n1)" || true
  [[ -n "$id" ]] || return 1
  printf '%s' "${id#https://standardebooks.org/ebooks/}"
}

# Standard Ebooks' own download links, in the order offered on an ebook's
# page; index 0 (plain .epub) doubles as the probe used to learn a new book's
# metadata, so it's usually already in place by the time the rest are fetched.
url_exts=(".epub" ".azw3" ".kepub.epub" "_advanced.epub")
local_exts=(".epub" ".azw3" ".kepub.epub" ".advanced.epub")

# How many of a book's formats are on disk. -s, not -e: a zero-length file is
# a download that was cut off (or a stray touch), and counting it as present
# would leave it that way forever - there is no later pass that would notice.
media_count() {
  local dir="$1" base="$2" ext n=0
  for ext in "${local_exts[@]}"; do
    [[ -s "$dir/$base$ext" ]] && n=$((n + 1))
  done
  printf '%s' "$n"
}

media_exists() {
  [[ "$(media_count "$1" "$2")" == "${#local_exts[@]}" ]]
}

index_file="$dest/.standardebooks-dl-index.tsv"

# A relative book path has 3 segments in the layout used before authors got a
# single directory (Last/First/Title) and 2 in the current one (Last, First/
# Title), so the count alone identifies a legacy path. Joining the two author
# segments back with ", " reproduces the sort name exactly: the old code split
# it at the first ", " only and rewrote neither half beyond sanitize's
# character replacement (which never introduces or removes a "/"). Mononym
# authors (Aesop, Homer, Anonymous...) always had one level and never match.
legacy_relpath() {
  local -a p
  IFS=/ read -ra p <<<"$1"
  [[ "${#p[@]}" == 3 ]]
}

current_relpath() {
  local -a p
  IFS=/ read -ra p <<<"$1"
  printf '%s, %s/%s' "${p[0]}" "${p[1]}" "${p[2]}"
}

# Moves a library built by an older version over to the current layout. This
# has to happen on every ordinary run, not once behind a flag: the ledger
# hands stored paths straight back to the downloader, which recreates them to
# fill in missing formats, so without this the layout would never change for
# any book already synced - only brand new ones would land in the right place.
# Idempotent, and local only (no requests): it just renames directories.
migrate_layout() {
  local dir rel new first surname moved=0 stuck=0
  while IFS= read -r -d '' dir; do
    rel="${dir#"$dest"/}"
    legacy_relpath "$rel" || continue
    # a book directory holds the book; anything else 3 deep is left alone
    [[ -n "$(find "$dir" -maxdepth 1 -type f -name '*.epub' -print -quit)" ]] || continue
    new="$(current_relpath "$rel")"
    if [[ -e "$dest/$new" ]]; then
      # these go straight to stderr rather than through warn(): the run-end
      # summaries collect download and cover failures, and a layout note
      # listed under those headings would just read as one of them
      echo "standardebooks-dl: warning: $rel: $new already exists" \
        "- left in place, merge it by hand" >&2
      stuck=$((stuck + 1))
      continue
    fi
    mkdir -p "$dest/${new%/*}"
    if mv -- "$dir" "$dest/$new"; then
      moved=$((moved + 1))
      # clear the two directory levels the move emptied, innermost first.
      # Plain rmdir (never -p, which would walk on up into the library root
      # and beyond) and each is skipped unless it is genuinely empty, so an
      # author with books still to migrate keeps their directory.
      first="${dir%/*}"
      surname="${first%/*}"
      rmdir -- "$first" 2>/dev/null || true
      [[ "$surname" != "$dest" ]] && { rmdir -- "$surname" 2>/dev/null || true; }
    else
      echo "standardebooks-dl: warning: $rel: could not move to $new" >&2
      stuck=$((stuck + 1))
    fi
  done < <(find "$dest" -mindepth 3 -maxdepth 3 -type d -print0)
  if [[ "$moved" -gt 0 || "$stuck" -gt 0 ]]; then
    echo "standardebooks-dl: layout: moved $moved book(s) to Last, First/Title" \
      "($stuck left behind)" >&2
  fi
}

# The on-disk move above is only half of it - the ledger's stored paths have to
# follow, or every migrated book looks missing and gets downloaded again into a
# freshly recreated legacy directory.
migrate_index() {
  local slug relpath changed=0 tmp="$index_file.migrating"
  [[ -s "$index_file" ]] || return 0
  : >"$tmp"
  while IFS=$'\t' read -r slug relpath; do
    [[ -n "$slug" ]] || continue
    if [[ -n "$relpath" ]] && legacy_relpath "$relpath"; then
      relpath="$(current_relpath "$relpath")"
      changed=$((changed + 1))
    fi
    printf '%s\t%s\n' "$slug" "$relpath" >>"$tmp"
  done <"$index_file"
  if [[ "$changed" -gt 0 ]]; then
    mv -- "$tmp" "$index_file"
    echo "standardebooks-dl: layout: $changed ledger path(s) updated" >&2
  else
    rm -f "$tmp"
  fi
}

# Recovers the ledger from the library itself. Every compatible epub on disk
# names the catalog entry it came from, so the whole slug -> directory mapping
# can be rebuilt offline, in place of re-downloading one epub per book just to
# find out where each one lives. The existing ledger wins wherever it already
# has a slug; only unknown ones are appended, which makes this safe to run over
# a ledger that is merely incomplete, and idempotent.
rebuild_index() {
  local epub dir rel slug scanned=0 added=0 unknown=0
  local -A seen=()
  while IFS=$'\t' read -r slug rel; do
    [[ -n "$slug" ]] && seen["$slug"]=1
  done <"$index_file"
  while IFS= read -r -d '' epub; do
    scanned=$((scanned + 1))
    dir="${epub%/*}"
    rel="${dir#"$dest"/}"
    if ! slug="$(epub_slug "$epub")"; then
      warn "$rel: no Standard Ebooks identifier in ${epub##*/} - not indexed"
      unknown=$((unknown + 1))
      continue
    fi
    [[ -n "${seen[$slug]:-}" ]] && continue
    printf '%s\t%s\n' "$slug" "$rel" >>"$index_file"
    seen["$slug"]=1
    added=$((added + 1))
  done < <(find "$dest" -type f -name '*.epub' \
    ! -name '*.kepub.epub' ! -name '*.advanced.epub' -print0)
  echo "standardebooks-dl: ledger: recovered $added book(s) from $scanned epub(s) on disk" >&2
  if [[ "$unknown" -gt 0 ]]; then
    echo "standardebooks-dl: ledger: $unknown epub(s) carried no identifier - see warnings" >&2
  fi
  return 0
}

# Both -n and the ordinary run read the ledger below, and -r appends to it.
touch "$index_file"

# -n is a dry run and stays read-only; the other modes migrate first so they
# never operate on a mix of both layouts.
if [[ "$list_only" == 0 ]]; then
  migrate_layout
  migrate_index
fi

# A ledger that is missing or empty beside a library that already has books in
# it is a lost ledger, not a first run - rebuild it from those books instead of
# treating the entire library as missing. -r rebuilds unconditionally further
# down and -n never writes, so this is for the ordinary run only.
if [[ "$list_only" == 0 && "$recheck" == 0 && ! -s "$index_file" ]] &&
  [[ -n "$(find "$dest" -type f -name '*.epub' \
    ! -name '*.kepub.epub' ! -name '*.advanced.epub' -print -quit)" ]]; then
  echo "standardebooks-dl: ledger is missing or empty - rebuilding it from the library..." >&2
  rebuild_index
fi

# -r: (re)generate cover.jpg for every book already on disk and recover the
# ledger from those same epubs, both read straight from local files. No catalog
# fetch, no network, no pacing - it only touches files already downloaded,
# overwriting existing covers so it doubles as a repair. The compatible .epub
# (not the .kepub.epub / .advanced.epub variants) is the one we read.
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
    echo "standardebooks-dl: $cover_failed epub(s) had no readable cover" >&2
  fi
  rebuild_index
  if [[ ${#warnings[@]} -gt 0 ]]; then
    echo "standardebooks-dl: warnings:" >&2
    for w in "${warnings[@]}"; do
      echo "standardebooks-dl:   warning: $w" >&2
    done
  fi
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# One request enumerates every published ebook on the site, sparing the 30-odd
# requests a page-by-page crawl of /ebooks?page=N would need.
#
# The catch is that the sitemap lists far more than the published catalog: a
# title gets an entry as soon as it is announced, years before its U.S. public-
# domain date, and those have no files to download - roughly two thirds of the
# ~4000 /ebooks URLs are such placeholders. Probing each of them costs a paced
# request per run, forever, which is what made a full sync take days.
#
# They are told apart without asking the site anything further: a published
# ebook has the online reader at /ebooks/<slug>/text, a placeholder has no
# subpages at all. So the /text URLs *are* the catalog - matched exactly, page
# for page, against every page of /ebooks?per-page=48 when this was written.
# Books with more than one translator are disambiguated with a 3rd path segment
# (/ebooks/author/book/translator), hence matching on the /text suffix rather
# than a fixed segment count; the final `grep /` drops anything that strips
# down to a single segment (an author page, were one ever to gain a /text).
echo "standardebooks-dl: fetching catalog..." >&2
sitemap="$tmpdir/sitemap.xml"
if ! curl -fsSL -A "$ua" --connect-timeout 15 --max-time 60 -o "$sitemap" "$base_url/sitemap"; then
  echo "standardebooks-dl: could not fetch $base_url/sitemap" >&2
  exit 1
fi
mapfile -t books < <(
  grep -oP '(?<=<loc>)https://standardebooks\.org/ebooks/[^<]+/text(?=</loc>)' "$sitemap" |
    sed -E 's#^https://standardebooks\.org/ebooks/##; s#/text$##' |
    grep '/' |
    sort -u
)
if [[ ${#books[@]} -eq 0 ]]; then
  echo "standardebooks-dl: sitemap yielded no ebooks - site layout may have changed" >&2
  exit 1
fi
echo "standardebooks-dl: ${#books[@]} published ebooks in the catalog" >&2

declare -A indexed_path
while IFS=$'\t' read -r slug relpath; do
  [[ -n "$slug" ]] && indexed_path["$slug"]="$relpath"
done <"$index_file"

fmt_duration() {
  local s="$1"
  if [[ "$s" -ge 86400 ]]; then
    printf '%dd%02dh' $((s / 86400)) $((s % 86400 / 3600))
  elif [[ "$s" -ge 3600 ]]; then
    printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
  elif [[ "$s" -ge 60 ]]; then
    printf '%dm' $((s / 60))
  else
    printf '%ds' "$s"
  fi
}

# ---- staying inside the site's download limit ------------------------------
#
# standardebooks.org limits *downloads* only - /ebooks/<slug>/downloads/... -
# and never the sitemap or the catalog pages, which stay available even while
# downloads are being refused. The rule (their site is open source, and this
# was confirmed against the live site) is two sliding windows over the
# downloads it has actually served to our IP: more than SHORT_MAX in
# SHORT_WINDOW seconds, or more than LONG_MAX in LONG_WINDOW seconds, answers
# 429 instead of the file.
#
# Two properties of it shape everything below. A refused request is rejected
# before it is recorded, so being blocked never deepens the hole and there is
# no penalty period to sit out - the block lifts the moment the window drains.
# And the windows slide, so the limit is not "wait N seconds between requests"
# but "keep the last six hours under a hundred".
#
# That makes a fixed delay the wrong tool: it either crawls when there is
# budget to spend or overruns when there isn't, and a fresh process has no idea
# what the one before it just spent. So we keep the same book the server keeps -
# a timestamp per download served to us - and consult it before every request.
# Waits then come out exactly right (sleep precisely until the oldest download
# ages out, never longer), and they survive restarts, which is what actually
# matters for a job measured in days.
#
# The ledger is per machine rather than per library, because the limit is keyed
# to our IP: two libraries synced from here draw on one budget.
SHORT_WINDOW=30
SHORT_MAX=35
LONG_WINDOW=21600 # 6 hours
LONG_MAX=100
# We time the wait by our clock and they enforce it by theirs, so step over a
# window boundary rather than landing exactly on it.
QUOTA_SLACK=20
# A floor on the gap between downloads. The quota above is the real constraint;
# this only stops us emptying a whole window's budget in a ninety-second burst,
# while still leaving it spendable in one sitting by someone who runs the script
# for an hour a day rather than continuously.
MIN_INTERVAL=30

quota_dir="${XDG_STATE_HOME:-$HOME/.local/state}/standardebooks-dl"
quota_file="$quota_dir/download-quota"
mkdir -p "$quota_dir"
touch "$quota_file"

# Reads the ledger into `stamps` (ascending), dropping everything that has
# aged out of the long window, and writes the pruned list back so it cannot
# grow without bound across a run of several days.
quota_load() {
  local now="$1" cutoff s
  cutoff=$((now - LONG_WINDOW))
  stamps=()
  while read -r s; do
    [[ "$s" =~ ^[0-9]+$ ]] || continue
    [[ "$s" -ge "$cutoff" ]] && stamps+=("$s")
  done <"$quota_file"
  if [[ ${#stamps[@]} -gt 0 ]]; then
    printf '%s\n' "${stamps[@]}" >"$quota_file"
  else
    : >"$quota_file"
  fi
}

quota_used() {
  local -a stamps
  quota_load "$(date +%s)"
  printf '%s' "${#stamps[@]}"
}

quota_record() {
  date +%s >>"$quota_file"
}

# How long until `count` drops to `limit`: the oldest (count - limit) entries
# have to age out, so it is the (count - limit)th oldest that we are waiting on.
quota_wait_for() {
  local -n arr="$1"
  local limit="$2" window="$3" now="$4" k
  [[ ${#arr[@]} -gt "$limit" ]] || return 0
  k=$((${#arr[@]} - limit))
  printf '%s' $((arr[k - 1] + window + QUOTA_SLACK - now))
}

# Blocks until one more download would be inside both windows. Called before
# every request that downloads a file - including the metadata probe, which is
# an ordinary epub download as far as the site is concerned.
quota_wait() {
  local now wait w s announced=0
  local -a stamps recent
  while :; do
    now=$(date +%s)
    quota_load "$now"
    recent=()
    for s in "${stamps[@]}"; do
      [[ "$s" -ge $((now - SHORT_WINDOW)) ]] && recent+=("$s")
    done

    wait=0
    w=$(quota_wait_for stamps "$LONG_MAX" "$LONG_WINDOW" "$now")
    [[ "${w:-0}" -gt "$wait" ]] && wait="$w"
    w=$(quota_wait_for recent "$SHORT_MAX" "$SHORT_WINDOW" "$now")
    [[ "${w:-0}" -gt "$wait" ]] && wait="$w"
    if [[ ${#stamps[@]} -gt 0 ]]; then
      w=$((MIN_INTERVAL - (now - stamps[${#stamps[@]} - 1])))
      [[ "$w" -gt "$wait" ]] && wait="$w"
    fi

    [[ "$wait" -le 0 ]] && return 0
    # Routine spacing passes in silence; a real wait for the six-hour window to
    # drain is hours long and has to say so, or the run looks hung.
    if [[ "$wait" -gt "$MIN_INTERVAL" && "$announced" == 0 ]]; then
      echo "standardebooks-dl: download quota spent (${#stamps[@]} in the last 6h)" \
        "- resuming in $(fmt_duration "$wait")" >&2
      announced=1
    fi
    sleep "$wait"
  done
}

# Fetches $1 into $2. Both --connect-timeout and --max-time are set because a
# server that throttles by stalling the connection instead of answering 429
# would otherwise hang curl forever - that's what happened before this was
# added. Returns 0 ok, 2 not found (404), 1 any other failure.
#
# A 429 here means the quota ledger disagrees with the server - it was lost,
# or something else on this IP (a browser, another machine behind the same NAT)
# has been downloading too. Since a refused request is never recorded, the only
# cost of waiting it out is time, so we do exactly that instead of giving up
# after a few tries and marking good books failed. Nothing can stay blocked
# longer than the six-hour window, so outlasting it is the escape hatch: a 429
# still coming back after that long is something other than the rate limit.
fetch_url() {
  local url="$1" out="$2" code backoff=60 blocked=0
  while :; do
    if ! code="$(curl -s -o "$out" -w '%{http_code}' \
      --connect-timeout 15 --max-time 180 -A "$ua" -L "$url")"; then
      return 1
    fi
    case "$code" in
      200) return 0 ;;
      404) return 2 ;;
      429)
        if [[ "$blocked" -ge $((LONG_WINDOW + 1800)) ]]; then
          warn "still rate-limited after $(fmt_duration "$blocked") - giving up on this file"
          return 1
        fi
        [[ "$blocked" == 0 ]] && echo "standardebooks-dl: rate-limited (429) with quota to spare" \
          "- the ledger is behind the server; waiting it out" >&2
        sleep "$backoff"
        blocked=$((blocked + backoff))
        backoff=$((backoff * 2))
        [[ "$backoff" -gt 900 ]] && backoff=900
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
  [[ -s "$target" ]] && return 0
  quota_wait
  # `|| rc=$?`, not a bare call then `rc=$?`: writeShellApplication runs
  # under set -e, and a plain non-zero-returning statement (even one whose
  # status is read on the next line) aborts the whole script right there -
  # every ordinary 404 would have silently killed the run before this fix.
  rc=0
  fetch_url "$dlbase$url_ext?source=download" "$target.part" || rc=$?
  # The site records what it served, so the ledger follows the same rule: a 200
  # counts against the quota whatever we end up doing with the bytes. A 404
  # (and a 429) is refused before it is recorded, and costs nothing.
  [[ "$rc" == 0 ]] && quota_record
  # an empty body answered with 200 is not a book; leaving it in place would
  # make the file look downloaded to every later run
  if [[ "$rc" == 0 && -s "$target.part" ]]; then
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
incomplete_list=()
todo=()
files_needed=0

# Work out the whole job before starting it. This costs nothing over the old
# decide-as-you-go loop (a stat per format, no requests), and it is what lets a
# run that takes hours say how much is left rather than only how far it has got.
# It is also exactly the set -n reports, so the two can't drift apart.
for slug in "${books[@]}"; do
  relpath="${indexed_path[$slug]:-}"
  if [[ -n "$relpath" ]] && media_exists "$dest/$relpath" "${relpath##*/}"; then
    already=$((already + 1))
    continue
  fi
  todo+=("$slug")
  # The quota is spent per file, not per book, so the count of files is what
  # the run's duration is actually made of. A book we have never seen costs a
  # full set; one already on disk costs only what it is short.
  if [[ -z "$relpath" ]]; then
    files_needed=$((files_needed + ${#local_exts[@]}))
    [[ "$list_only" == 1 ]] && missing_list+=("$slug")
  else
    have="$(media_count "$dest/$relpath" "${relpath##*/}")"
    files_needed=$((files_needed + ${#local_exts[@]} - have))
    # -n's two lists are that same set, split by whether anything is on disk
    # yet: books missing entirely, and books short a format or two.
    [[ "$list_only" == 1 ]] && incomplete_list+=("$slug ($have/${#local_exts[@]} formats)")
  fi
done

# The site allows LONG_MAX files per LONG_WINDOW and nothing we can do changes
# that, so the finish time follows from the file count alone - worth saying out
# loud before a job that runs for days, and worth saying accurately, because
# the previous pacing promised hours and then delivered a wall of 429s.
quota_now="$(quota_used)"
eta_seconds=$((files_needed * LONG_WINDOW / LONG_MAX))

if [[ "$list_only" == 1 ]]; then
  if [[ ${#missing_list[@]} -gt 0 ]]; then
    printf '%s\n' "${missing_list[@]}"
  fi
  if [[ ${#incomplete_list[@]} -gt 0 ]]; then
    printf '%s\n' "${incomplete_list[@]}"
  fi
  echo "standardebooks-dl: ${#missing_list[@]} of $total ebooks not in the library yet" >&2
  if [[ ${#incomplete_list[@]} -gt 0 ]]; then
    echo "standardebooks-dl: ${#incomplete_list[@]} more are in the library but missing formats" >&2
  fi
  echo "standardebooks-dl: $files_needed files to fetch;" \
    "at the site's limit of $LONG_MAX per $(fmt_duration "$LONG_WINDOW") that is about $(fmt_duration "$eta_seconds")" >&2
  echo "standardebooks-dl: quota: $quota_now downloads in the last" \
    "$(fmt_duration "$LONG_WINDOW") (limit $LONG_MAX)" >&2
  exit 0
fi

remaining=${#todo[@]}
handled=0
started=$SECONDS

# One line per book actually worked on, so an unattended run can be checked in
# on: position, what is left, and how long that looks like taking. The estimate
# is elapsed time per book handled so far, extrapolated - books cost wildly
# different amounts (a not-yet-released title is one 404, a new book is four
# downloads), so it is an average settling over a long run, not a countdown.
# handled is incremented before every call, so it is never 0 here.
progress() {
  local outcome="$1" what="$2" left tail=""
  left=$((remaining - handled))
  if [[ "$left" -gt 0 ]]; then
    tail=" - $left left, ~$(fmt_duration $(((SECONDS - started) * left / handled)))"
  fi
  echo "standardebooks-dl: [$handled/$remaining] $outcome: $what$tail"
}

if [[ "$remaining" -eq 0 ]]; then
  echo "standardebooks-dl: all $total ebooks are already in the library - nothing to do" >&2
else
  echo "standardebooks-dl: $already of $total already complete - $remaining to fetch" >&2
  echo "standardebooks-dl: $files_needed files at $LONG_MAX per $(fmt_duration "$LONG_WINDOW")" \
    "(the site's limit) - about $(fmt_duration "$eta_seconds");" \
    "$quota_now spent in the last $(fmt_duration "$LONG_WINDOW")" >&2
  echo "standardebooks-dl: safe to interrupt - the quota is remembered between runs" >&2
fi

for slug in "${todo[@]}"; do
  handled=$((handled + 1))
  relpath="${indexed_path[$slug]:-}"

  dlbase="$base_url/ebooks/$slug/downloads/${slug//\//_}"

  if [[ -z "$relpath" ]]; then
    # Not in the ledger: probe with the compatible epub first. A 404 here means
    # the catalog offers no files for the slug - normally impossible now that
    # only published ebooks are enumerated, but a book caught mid-publication
    # or renamed since the sitemap was generated would land here. Not a failure
    # (the next run picks it up); any other error is, and is retried too.
    epub_tmp="$tmpdir/probe.epub"
    rm -f "$epub_tmp"
    quota_wait
    rc=0
    fetch_url "$dlbase.epub?source=download" "$epub_tmp" || rc=$?
    [[ "$rc" == 0 ]] && quota_record
    if [[ "$rc" != 0 ]]; then
      if [[ "$rc" == 2 ]]; then
        unavailable=$((unavailable + 1))
        progress "no files offered" "$slug"
      else
        warn "$slug: failed to fetch compatible epub"
        failed=$((failed + 1))
        progress "failed" "$slug"
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
      progress "failed" "$slug"
      continue
    fi
    author_fileas="$(unescape_xml "$author_fileas")"
    title="$(unescape_xml "$title")"

    # file-as is already the "Last, First" sort name Calibre's {author_sort}
    # uses (and a bare mononym - Aesop, Homer, Anonymous... - where there is
    # no first name), so it becomes the author directory as-is. It stays one
    # directory level: splitting it on the comma would make Calibre and
    # Jellyfin read the surname as the author and the first name as a book.
    author_dir="$(sanitize "$author_fileas")"
    base="$(sanitize "$title")"

    titledir="$dest/$author_dir/$base"
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
  if [[ -s "$titledir/$base.epub" && ! -s "$titledir/cover.jpg" ]]; then
    if extract_cover "$titledir/$base.epub" "$titledir/cover.jpg"; then
      covers=$((covers + 1))
    else
      warn "$relpath: could not extract cover from epub"
    fi
  fi

  if [[ "$ok" == 1 ]]; then
    downloaded=$((downloaded + 1))
    progress "downloaded" "$relpath"
  else
    failed=$((failed + 1))
    progress "incomplete" "$relpath"
  fi
done

echo >&2
echo "standardebooks-dl: ---- run summary ----" >&2
echo "standardebooks-dl: $already of $total ebooks were already in the library" >&2
if [[ "$remaining" -gt 0 ]]; then
  echo "standardebooks-dl: downloaded $downloaded of the $remaining attempted" \
    "in $(fmt_duration $((SECONDS - started)))" >&2
fi
if [[ "$covers" -gt 0 ]]; then
  echo "standardebooks-dl: wrote $covers new cover image(s)" >&2
fi
if [[ "$unavailable" -gt 0 ]]; then
  echo "standardebooks-dl: $unavailable ebook(s) skipped - the catalog lists them but offers no files" >&2
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
