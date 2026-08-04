usage() {
  # requested help goes to stdout; usage errors go to stderr
  [[ "${1:-0}" == 0 ]] || exec >&2
  cat <<'EOF'
Usage: drtv-dl [-d DIR] [-l] [-n] [-r] [-c] [URL...] [extra yt-dlp options...]

Download one or more DRTV (dr.dk/drtv) series, seasons or films,
named so Jellyfin picks them up:

  Series Name/Season 10/Series Name - S10E05 - Episode Title.ext
  Film Name (1968)/Film Name (1968).ext

Episodes whose file already exists on disk are skipped up front via a cheap
playlist scan (one API request per season) instead of being re-extracted
one webpage at a time on every run. Films never appear in a playlist, so
they are probed with a metadata-only extraction instead; either way,
existing video files are never re-downloaded or rewritten.

Jellyfin NFO files and artwork are generated alongside the downloads:
tvshow.nfo, poster and season posters per series, an .nfo and thumb image
per episode, and an .nfo plus poster per film. The NFOs carry
<lockdata>true</lockdata>, so Jellyfin keeps DR's metadata instead of
guessing (often wrongly) via TVDB/TMDB.

With no URLs, they are read from a drtv-series.txt in the library root
(see -d): one series or season URL per line; blank lines, #-comments and
anything after the URL are ignored. Keep one next to your series and
staying current is just:

  cd /mnt/series && drtv-dl -n    # list episodes you don't have yet
  cd /mnt/series && drtv-dl       # download them

An episode whose video is on disk but whose .nfo is missing (an interrupted
run, or a library predating the sidecars) is re-extracted on its own with
--skip-download, so an ordinary run repairs the gap for the few episodes
that have one instead of needing -r over the whole library.

Progress is reported per finished file against the number the run set out to
fetch, with a rolling estimate of the time left:

  drtv-dl: [7/23] finished: Gurli Gris/Season 10/... - 16 left, ~1h12m

Options:
  -d DIR   root of your TV library (default: current directory)
  -l       don't download; print the episode links instead, one per line
           (e.g. drtv-dl -l URL > links.txt)
  -n       don't download; list videos that are not on disk yet, one per
           line, plus a count of those missing their NFO sidecar. Films are
           probed one request each; series/seasons cost one per season.
  -r       recheck every episode with a full extraction even if its file
           exists, regenerating NFOs and images along the way (use it when
           renames make the fast skip misjudge - routine sidecar gaps are
           repaired by an ordinary run); video files are left untouched
  -c       don't download; delete yt-dlp's leftover scratch files (.part,
           .part-FragN, .ytdl and per-format streams) from runs that were
           interrupted. Every run reports what it finds. Don't use it while
           another drtv-dl is downloading into the same library.
  -h       show this help

Several URLs can be given; anything that isn't a DRTV URL is passed
straight to yt-dlp. Options must come before the first URL: anything
after it is passed through, so a trailing -n reaches yt-dlp (where it
means --netrc) instead of enabling check mode.
EOF
  exit "${1:-0}"
}

dest="."
links_only=0
check_only=0
recheck=0
clean_only=0
while getopts ":d:clnrh" opt; do
  case "$opt" in
    d) dest="$OPTARG" ;;
    c) clean_only=1 ;;
    l) links_only=1 ;;
    n) check_only=1 ;;
    r) recheck=1 ;;
    h) usage ;;
    :)
      echo "drtv-dl: option -$OPTARG requires an argument" >&2
      usage 1
      ;;
    *)
      echo "drtv-dl: unknown option -$OPTARG" >&2
      usage 1
      ;;
  esac
done
shift $((OPTIND - 1))
if [[ $((links_only + check_only + recheck + clean_only)) -gt 1 ]]; then
  echo "drtv-dl: -l, -n, -r and -c cannot be combined" >&2
  exit 1
fi

# An interrupted run leaves yt-dlp's scratch files behind: the per-format
# streams it had not merged yet, fragment parts, resume data. media_exists
# below ignores them (its single-token extension rule), so they never cause a
# wrong skip - but nothing removes them either, and a half-fetched video stream
# is not free. Only yt-dlp's own scratch names are matched: subtitle and image
# files are left alone, since those may well be the user's own.
find_leftovers() {
  find "$dest" -regextype posix-extended -type f \
    \( -name '*.part' -o -name '*.part-Frag*' -o -name '*.ytdl' -o -name '*.temp' \
    -o -name '*.fvideo_*' -o -name '*.faudio_*' -o -regex '.*\.f[0-9]+\.[a-z0-9]+' \) \
    -print0
}

fmt_size() {
  local b="$1"
  if [[ "$b" -ge 1073741824 ]]; then
    printf '%d.%d GB' $((b / 1073741824)) $((b % 1073741824 * 10 / 1073741824))
  elif [[ "$b" -ge 1048576 ]]; then
    printf '%d MB' $((b / 1048576))
  else
    printf '%d kB' $((b / 1024))
  fi
}

fmt_duration() {
  local s="$1"
  if [[ "$s" -ge 3600 ]]; then
    printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
  elif [[ "$s" -ge 60 ]]; then
    printf '%dm' $((s / 60))
  else
    printf '%ds' "$s"
  fi
}

# -c needs no URLs, so it runs before the subscription-file fallback below.
if [[ "$clean_only" == 1 ]]; then
  removed=0
  freed=0
  while IFS= read -r -d '' f; do
    size="$(stat -c %s "$f" 2>/dev/null || echo 0)"
    if rm -f -- "$f"; then
      removed=$((removed + 1))
      freed=$((freed + size))
      echo "drtv-dl: removed ${f#"$dest"/}"
    fi
  done < <(find_leftovers)
  if [[ "$removed" -eq 0 ]]; then
    echo "drtv-dl: no leftover files in $dest" >&2
  else
    echo "drtv-dl: removed $removed leftover file(s), freeing $(fmt_size "$freed")" >&2
  fi
  exit 0
fi

# With no URLs, fall back to the subscription file in the library root.
subs="$dest/drtv-series.txt"
if [[ $# -eq 0 ]]; then
  if [[ ! -f "$subs" ]]; then
    echo "drtv-dl: no URLs given and no $subs to read them from" >&2
    usage 1
  fi
  sub_urls=()
  while read -r url _ || [[ -n "$url" ]]; do
    url="${url%$'\r'}"
    if [[ -n "$url" && "$url" != \#* ]]; then
      sub_urls+=("$url")
    fi
  done <"$subs"
  if [[ ${#sub_urls[@]} -eq 0 ]]; then
    echo "drtv-dl: no URLs in $subs" >&2
    exit 1
  fi
  echo "drtv-dl: using ${#sub_urls[@]} URLs from $subs" >&2
  set -- "${sub_urls[@]}"
fi

# Warnings are printed as they happen, but an overnight run buries them in
# thousands of progress lines - collect them so the summary at the end can
# repeat them all in one place.
warnings=()
warn() {
  echo "drtv-dl: warning: $*" >&2
  warnings+=("$*")
}

# DRTV's site puts the *season* URL in the address bar while you browse a
# show, so it is easy to subscribe to one season thinking it is the whole
# series. Warn when a season URL names a show that has more seasons.
season_api='https://production-cdn.dr-massive.com/api/page?device=web_browser&item_detail_expand=all&lang=da&max_list_prefetch=3&path='
check_single_season() {
  local url="$1" path msg
  path="${url#*://*/drtv}"
  msg="$(curl -fsSL -m 10 "$season_api${path%/}" 2>/dev/null | jq -r --arg url "$url" '
    .entries[0].item as $item
    | ($item.show.seasons.items | length) as $n
    | if $n > 1 then
        "\($url) is only season \($item.seasonNumber) of \"\($item.show.title)\", which has \($n) seasons;"
        + " use https://www.dr.dk/drtv\($item.show.path) to get every season"
      else empty end' 2>/dev/null)" || return 0
  if [[ -n "$msg" ]]; then
    warn "$msg"
  fi
}

# yt-dlp's DRTV extractor only matches the canonical slug URLs
# (/drtv/serie/gurli-gris_7190). Bare-ID URLs like /drtv/serie/7190
# redirect there in a browser, so resolve them the same way first.
args=()
playlist_urls=()
# Everything that can't be covered by the cheap playlist scan below (films,
# direct episode links, and - under -r - the playlists too) goes through a
# --skip-download probe instead; passthrough yt-dlp options tag along.
probe_args=()
probe_has_url=0
# how many of probe_args are URLs rather than passthrough yt-dlp options, so -n
# can tell when a probe came back with fewer answers than it asked questions
probe_url_count=0
for url in "$@"; do
  if [[ "$url" =~ ^https?://(www\.)?dr\.dk/drtv/(serie|saeson)/[0-9]+/?$ ]]; then
    # One GET serves both detection paths: -w appends the post-redirect URL
    # after the body, and the body is kept for the canonical-<link> fallback
    # used when the server answers 200 with the SPA page instead of redirecting.
    page="$(curl -fsSL -m 20 -w '\n%{url_effective}' "$url" 2>/dev/null)" || page=""
    resolved="${page##*$'\n'}"
    page="${page%$'\n'*}"
    if [[ ! "$resolved" =~ _[0-9]+/?$ ]]; then
      resolved="$(grep -oP '<link[^>]*rel="canonical"[^>]*href="\K[^"]+' <<<"$page" | head -n 1)" ||
        resolved="$(grep -oP '<link[^>]*href="\K[^"]+(?="[^>]*rel="canonical")' <<<"$page" | head -n 1)" ||
        resolved=""
    fi
    [[ "$resolved" == /* ]] && resolved="https://www.dr.dk$resolved"
    if [[ -n "$resolved" && "$resolved" != "$url" ]]; then
      echo "drtv-dl: resolved $url -> $resolved" >&2
      url="$resolved"
    else
      warn "could not resolve $url to its canonical (slug) form;" \
        "yt-dlp may not recognise it - use the URL from your browser's address bar"
    fi
  fi
  if [[ "$url" =~ ^https?://(www\.)?dr\.dk/drtv/(serie|saeson)/[^/]+_[0-9]+/?$ ]]; then
    playlist_urls+=("$url")
    if [[ "$recheck" == 1 ]]; then
      probe_args+=("$url")
      probe_has_url=1
    fi
    if [[ "$url" == */drtv/saeson/* ]]; then
      check_single_season "$url"
    fi
  else
    # films and direct episode links; under -n these are probed for their
    # filename only, which is one request each and no info.json
    probe_args+=("$url")
    if [[ "$url" == http* ]]; then
      probe_has_url=1
      probe_url_count=$((probe_url_count + 1))
    fi
  fi
  args+=("$url")
done

if [[ "$links_only" == 1 ]]; then
  # A flat pass over a series URL yields its season playlists, not episodes
  # (the same reason the skip scan below expands series first), so swap each
  # series for its seasons here. If the expansion comes back empty, keep the
  # original URL so yt-dlp still gets a chance to report what's wrong with it.
  links_args=()
  for url in "${args[@]}"; do
    if [[ "$url" =~ ^https?://(www\.)?dr\.dk/drtv/serie/[^/]+_[0-9]+/?$ ]]; then
      expanded=()
      while IFS= read -r line; do
        [[ "$line" == http* ]] && expanded+=("$line")
      done < <(yt-dlp --ignore-errors --flat-playlist --print url "$url" 2>/dev/null || true)
      if [[ ${#expanded[@]} -gt 0 ]]; then
        links_args+=("${expanded[@]}")
      else
        links_args+=("$url")
      fi
    else
      links_args+=("$url")
    fi
  done
  exec yt-dlp --flat-playlist --print webpage_url "${links_args[@]}"
fi

# Scratch files for the rest of the run: the throwaway download archive fed
# to yt-dlp, the list of files this run actually downloaded (printed in the
# summary), and yt-dlp's captured stderr (its WARNING/ERROR lines are
# repeated in the summary, where they can't scroll out of sight).
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
archive="$tmpdir/archive"
manifest="$tmpdir/manifest"
errlog="$tmpdir/errlog"
: >"$archive"
: >"$manifest"
: >"$errlog"

# One template serves both layouts. Films (/drtv/program/ URLs) carry no
# series/season/episode fields, so every %(field&...|)s piece conditioned on
# them renders empty and only the movie_name parts (synthesised below) remain:
#
#   episode:  Series/Season 01/Series - S01E05 - Episode.ext
#   film:     Film Name (1968)//Film Name (1968).ext
#
# The season directory must remain its own literal path segment (slashes
# inside %(...&...)s replacements are sanitised into "⧸"), so the film path
# keeps an empty component; "//" collapses and the file lands one level up.
# The episode thumb shares the same base so Jellyfin pairs them up.
#
# dest_tmpl is only for -o templates: yt-dlp expands %(...)s anywhere in the
# path, so a "%" in the library root itself must be doubled to stay literal.
dest_tmpl="${dest//\%/%%}"
outbase="$dest_tmpl/%(series,movie_name)s/%(season_number&Season {:02d}|)s/%(series&{} - |)s%(season_number&S{:02d}|)s%(episode_number&E{:02d}|)s%(series& - |)s%(movie_name,episode,title)s"
outtmpl="$outbase.%(ext)s"

# DRTV episode titles repeat the series name ("Gurli Gris: Slemme skildpadde");
# strip that prefix from episode/title, but only when it matches the series
# exactly (the backreference), so unrelated colons in titles are left alone.
# The last two rules build movie_name = "Title (Year)" for films, keyed on
# series being absent (it renders as the NA placeholder), with the year
# dropped when DR doesn't provide one. Every regex ends in an always-matching
# |.* branch: unmatched named groups are simply skipped, whereas a failed
# match would print a "Could not interpret" warning per rule and item.
meta_args=(
  --parse-metadata '%(series)s|%(episode)s:^(?:(?P<series>.+)\|(?P=series): (?P<episode>.+)|.*)$'
  --parse-metadata '%(series)s|%(title)s:^(?:(?P<series>.+)\|(?P=series): (?P<title>.+)|.*)$'
  --parse-metadata '%(series)s|%(title)s:^(?:NA\|(?P<movie_name>.+)|.*)$'
  --parse-metadata '%(series)s|%(title)s (%(release_year)s):^(?:NA\|(?P<movie_name>.+ \(\d{4}\))|.*)$'
)

# A video counts as "on disk" when a file with the expected base name and a
# single-token extension exists: leftovers like .part/.ytdl/.f<id>.mp4 from
# aborted runs must not count as done, and neither do the NFO/image sidecars
# generated below.
media_exists() {
  local f ext
  for f in "$1".*; do
    [[ -e "$f" ]] || continue
    ext="${f#"$1".}"
    [[ "$ext" == *.* ]] && continue
    case "$ext" in nfo | jpg | jpeg | png | webp) continue ;; esac
    return 0
  done
  return 1
}

# Re-running on a series normally re-extracts every episode (webpage + stream
# data) just to learn its filename and say "has already been downloaded" - and
# then re-runs the Metadata postprocessor on the existing file. To skip all of
# that without keeping a persistent archive file, scan the season playlists
# flat (the season API response already carries series/season/episode fields,
# so --print filename yields the real output path with only the extension
# unknown), and feed the episodes whose file already exists to yt-dlp as a
# throwaway --download-archive: yt-dlp matches archive ids against the URL
# slug before extraction, so those episodes cost no requests at all. The
# archive is deleted afterwards - the files on disk stay the source of truth.
# -n reuses the same scan, but prints the episodes whose file is missing
# instead of downloading them.
#
# The scan also notices episodes whose video is on disk but whose .nfo is not
# (a run interrupted between the two, or a library older than the sidecars).
# Those are neither skipped nor downloaded: they join the --skip-download probe
# below, which regenerates the sidecars for one episode at the cost of one
# extraction. Before this, the only cure was -r over the whole library - a full
# extraction of every episode to repair a handful. The thumbnail is not part of
# the test: DR does not have one for every video, and an episode that will
# never have one would otherwise be re-probed on every single run.
skip_args=()
scanned=0
present=0
sidecar_urls=()
sidecar_missing=0
# bases the playlist scan has already accounted for, so the probe below doesn't
# count the sidecar repairs it hands over a second time
declare -A scanned_bases=()
if [[ "$check_only" == 1 && ${#playlist_urls[@]} -eq 0 && "$probe_has_url" == 0 ]]; then
  echo "drtv-dl: -n: no URLs to check" >&2
  exit 1
fi
if [[ "$recheck" == 0 && ${#playlist_urls[@]} -gt 0 ]]; then
  season_urls=()
  serie_urls=()
  for url in "${playlist_urls[@]}"; do
    if [[ "$url" == */drtv/serie/* ]]; then
      serie_urls+=("$url")
    else
      season_urls+=("$url")
    fi
  done
  # A flat scan of a series stops at its seasons, so expand those first.
  if [[ ${#serie_urls[@]} -gt 0 ]]; then
    while IFS= read -r line; do
      [[ "$line" == http* ]] && season_urls+=("$line")
    done < <(yt-dlp --ignore-errors --flat-playlist --print url "${serie_urls[@]}" 2>/dev/null || true)
  fi

  if [[ ${#season_urls[@]} -gt 0 ]]; then
    while IFS= read -r id && IFS= read -r name && IFS= read -r url; do
      scanned=$((scanned + 1))
      # flat-playlist entries have no known extension, so this is ".NA" - but
      # strip whatever is there, the same way the film probe below has to
      base="${name%.*}"
      scanned_bases["$base"]=1
      if media_exists "$base"; then
        present=$((present + 1))
        if [[ -e "$base.nfo" ]]; then
          if [[ "$check_only" == 0 ]]; then
            printf 'drtv %s\n' "$id" >>"$archive"
          fi
        else
          sidecar_missing=$((sidecar_missing + 1))
          if [[ "$check_only" == 0 ]]; then
            sidecar_urls+=("$url")
          fi
        fi
      elif [[ "$check_only" == 1 ]]; then
        printf '%s\n' "${base#"$dest/"}"
      fi
    done < <(yt-dlp --ignore-errors --flat-playlist "${meta_args[@]}" \
      --output "$outtmpl" --print id --print filename --print url "${season_urls[@]}" 2>/dev/null || true)
    if [[ "$check_only" == 0 ]]; then
      if [[ "$scanned" -gt 0 ]]; then
        echo "drtv-dl: $present of $scanned episodes already on disk; skipping those" >&2
        skip_args=(--download-archive "$archive")
      else
        warn "playlist scan found no episodes; checking everything"
      fi
      if [[ ${#sidecar_urls[@]} -gt 0 ]]; then
        echo "drtv-dl: $sidecar_missing episode(s) on disk have no .nfo; re-extracting just those" >&2
        probe_args+=("${sidecar_urls[@]}")
        probe_has_url=1
      fi
    fi
  elif [[ "$check_only" == 1 && "$probe_has_url" == 0 ]]; then
    echo "drtv-dl: -n: could not expand the URLs into season playlists" >&2
    exit 1
  fi
fi

# -n for everything a playlist can't cover: films and direct episode links.
# One --skip-download extraction each buys the output filename, which is all
# the on-disk test needs - and nothing is written, not even an info.json.
if [[ "$check_only" == 1 && "$probe_has_url" == 1 ]]; then
  probed=0
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    probed=$((probed + 1))
    scanned=$((scanned + 1))
    # a full extraction knows the real extension, where the flat playlist scan
    # only ever gets NA - strip whichever it is, or media_exists would look for
    # "Film (1990).mp4.*" and pronounce a film it already has missing
    base="${name%.*}"
    if media_exists "$base"; then
      present=$((present + 1))
    else
      rel="${base#"$dest/"}"
      # films render as "Film (1990)//Film (1990)": the template keeps an empty
      # season component so the season stays its own path segment. The
      # filesystem collapses it; the listing shouldn't show it.
      printf '%s\n' "${rel//\/\//\/}"
    fi
  done < <(yt-dlp --ignore-errors --skip-download --no-write-info-json \
    "${meta_args[@]}" --output "$outtmpl" --print filename "${probe_args[@]}" 2>/dev/null || true)
  # DR takes films down again; a URL that answers nothing would otherwise be
  # missing from the list without a word, which reads as "you have it already"
  if [[ "$probed" -lt "$probe_url_count" ]]; then
    warn "$((probe_url_count - probed)) of $probe_url_count film/episode URLs could not be checked" \
      "- gone from DR, or a URL that no longer resolves"
  fi
fi

if [[ "$check_only" == 1 ]]; then
  if [[ "$scanned" -eq 0 ]]; then
    echo "drtv-dl: warning: nothing could be scanned" >&2
    exit 1
  fi
  echo "drtv-dl: $((scanned - present)) of $scanned videos not on disk yet" >&2
  if [[ "$sidecar_missing" -gt 0 ]]; then
    echo "drtv-dl: $sidecar_missing more are on disk without an .nfo - an ordinary run repairs those" >&2
  fi
  exit 0
fi

# yt-dlp re-runs its metadata/subtitle embedding on any file that already
# exists, rewriting the whole video in place just to change nothing - on a
# NAS that takes minutes per file, silently. The playlist scan above spares
# episodes, but films never appear in a playlist, and -r bypasses the scan
# on purpose. Probe those URLs with --skip-download first: the extraction
# refreshes each video's info.json and thumbnail (the NFO pass below turns
# them into fresh sidecars), and every video whose file is already on disk
# goes into the download archive, so the download run only touches what is
# actually missing.
if [[ "$probe_has_url" == 1 ]]; then
  {
    yt-dlp --ignore-errors --skip-download \
      --write-info-json \
      --write-thumbnail --convert-thumbnails jpg \
      "${meta_args[@]}" \
      --output "$outtmpl" \
      --output "thumbnail:$outbase-thumb.%(ext)s" \
      --output "pl_thumbnail:$dest_tmpl/%(series)s/%(season_number&season{:02d}-poster|poster)s.%(ext)s" \
      --output "pl_infojson:$dest_tmpl/%(series)s/%(season_number&season{:02d}|tvshow)s" \
      "${probe_args[@]}" 2>&1 1>&3 | tee -a "$errlog" >&2
  } 3>&1 || true
  probe_scanned=0
  probe_present=0
  while IFS= read -r -d '' f; do
    base="${f%.info.json}"
    case "${base##*/}" in tvshow | season[0-9]*) continue ;; esac
    # an episode handed over by the playlist scan for sidecar repair is already
    # in its tallies; counting it again here would inflate both halves of the
    # "N of M already on disk" summary
    if [[ -z "${scanned_bases[$base]:-}" ]]; then
      probe_scanned=$((probe_scanned + 1))
      if media_exists "$base"; then
        probe_present=$((probe_present + 1))
      fi
    fi
    if media_exists "$base"; then
      # Two archive lines per video. The final id is what films and direct
      # URLs are checked against (after their unavoidable re-extraction);
      # season-playlist entries are checked against the URL slug *before*
      # extraction, so the slug line spares every already-present episode a
      # second full extraction when -r descends the playlists again.
      jq -r '"\(.extractor_key | ascii_downcase) \(.id)",
        "\(.extractor_key | ascii_downcase) \(.webpage_url // "" | rtrimstr("/") | split("/") | (last // "") | select(. != ""))"' \
        "$f" >>"$archive" || true
    fi
  done < <(find "$dest" -name '*.info.json' -type f -print0)
  scanned=$((scanned + probe_scanned))
  present=$((present + probe_present))
  if [[ "$probe_present" -gt 0 ]]; then
    echo "drtv-dl: $probe_present of $probe_scanned rechecked videos already on disk; leaving their files untouched" >&2
    skip_args=(--download-archive "$archive")
  fi
fi

# Besides the media file, have yt-dlp write the raw material for Jellyfin
# sidecars: an info.json per video (turned into an .nfo below and deleted),
# a landscape thumb next to each episode/film, and - via the playlist
# metafiles written for every series/season playlist it descends into -
# a tvshow info.json plus portrait poster/season posters in the series
# directory. Playlist metafiles are refreshed on every run, even when all
# episodes are skipped through the download archive.
#
# The download progress bar goes quiet during the slow tail of each episode
# (fragment merge, metadata/subtitle embedding, the move onto a NAS), which
# looks like a stall overnight. Announce every file the moment it is fully
# written, and record it for the summary (the wc runs when the hook fires,
# so the count grows as the run progresses). The logic lives in a scratch
# script because yt-dlp echoes the entire --exec command line before running
# it - this keeps that echo down to the script path plus the file name.
#
# Both scans above have run by now, so the number of videos this run set out to
# fetch is known: everything they looked at, minus what was already on disk.
# That turns the announcement into a position rather than a running total, with
# a projection from the average so far. It stays honest when the denominator
# can't be trusted (nothing scannable, or more files arriving than predicted -
# a season gaining episodes mid-run): past the total, it falls back to the
# plain count rather than printing a negative or a nonsense estimate.
remaining=0
if [[ "$scanned" -gt "$present" ]]; then
  remaining=$((scanned - present))
fi
started=$(date +%s)
# yt-dlp reports an absolute filepath; the library root is the same for every
# line of a run, so the announcements and the summary listing drop it
dest_abs="$(realpath -m -- "$dest")"

announce="$tmpdir/announce"
cat >"$announce" <<EOF
#!/bin/sh
rel="\$1"
case "\$rel" in
  '$dest_abs'/*) rel="\${rel#'$dest_abs'/}" ;;
esac
printf '%s\n' "\$rel" >>'$manifest'
n=\$(wc -l <'$manifest')
left=\$(($remaining - n))
if [ '$remaining' -gt 0 ] && [ "\$left" -ge 0 ]; then
  if [ "\$left" -gt 0 ]; then
    eta=\$(((\$(date +%s) - $started) * left / n))
    if [ "\$eta" -ge 3600 ]; then
      human="\$((eta / 3600))h\$(printf '%02d' \$((eta % 3600 / 60)))m"
    elif [ "\$eta" -ge 60 ]; then
      human="\$((eta / 60))m"
    else
      human="\${eta}s"
    fi
    printf 'drtv-dl: [%s/%s] finished: %s - %s left, ~%s\n' "\$n" '$remaining' "\$rel" "\$left" "\$human"
  else
    printf 'drtv-dl: [%s/%s] finished: %s\n' "\$n" '$remaining' "\$rel"
  fi
else
  printf 'drtv-dl: finished (%s this run): %s\n' "\$n" "\$rel"
fi
EOF
chmod +x "$announce"

# no exec (the shell kind): the trap above must clean up the scratch dir, and
# the NFO pass below must still run (yt-dlp's exit status is re-raised at the
# end). stderr is teed through the pipeline - shown live and kept for the
# summary; the pipeline keeps stdout (fd 3) untouched so the progress bar
# still renders on the terminal.
status=0
{
  yt-dlp \
    --embed-metadata \
    --sub-langs all --embed-subs \
    --concurrent-fragments 6 \
    --write-info-json \
    --write-thumbnail --convert-thumbnails jpg \
    "${meta_args[@]}" \
    "${skip_args[@]}" \
    --output "$outtmpl" \
    --output "thumbnail:$outbase-thumb.%(ext)s" \
    --output "pl_thumbnail:$dest_tmpl/%(series)s/%(season_number&season{:02d}-poster|poster)s.%(ext)s" \
    --output "pl_infojson:$dest_tmpl/%(series)s/%(season_number&season{:02d}|tvshow)s" \
    --exec "after_move:$announce %(filepath)q" \
    "${args[@]}" 2>&1 1>&3 | tee -a "$errlog" >&2
} 3>&1 || status=$?

# Turn every info.json from this run into a Jellyfin NFO
# (https://jellyfin.org/docs/general/server/metadata/nfo/) and delete it -
# the jsons never outlive a run, so any file found here is fresh.
# <lockdata>true</lockdata> stops Jellyfin's online scrapers from
# overwriting DR's metadata; the mismatched TVDB/TMDB guesses are exactly
# what these files exist to prevent.
xml_esc='def esc: tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");'
xml_decl='"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>",'

tvshow_nfo="$xml_esc $xml_decl"'
  "<tvshow>",
  "  <title>\(.series // .title | esc)</title>",
  (if .description then "  <plot>\(.description | esc)</plot>" else empty end),
  "  <lockdata>true</lockdata>",
  "</tvshow>"'

# shellcheck disable=SC2016 # $root is a jq variable, not a shell one
media_nfo="$xml_esc"'
  (if .series then "episodedetails" else "movie" end) as $root | '"$xml_decl"'
  "<\($root)>",
  "  <title>\((if .series then .episode else null end) // .title | esc)</title>",
  (if .series == null and .release_year then "  <year>\(.release_year)</year>" else empty end),
  (if .season_number != null then "  <season>\(.season_number)</season>" else empty end),
  (if .episode_number != null then "  <episode>\(.episode_number)</episode>" else empty end),
  (if .description then "  <plot>\(.description | esc)</plot>" else empty end),
  (if .release_timestamp then "  <\(if .series then "aired" else "premiered" end)>\((.release_timestamp | todate)[:10])</\(if .series then "aired" else "premiered" end)>" else empty end),
  (if .duration then "  <runtime>\(.duration / 60 | floor)</runtime>" else empty end),
  "  <lockdata>true</lockdata>",
  "</\($root)>"'

# When only a season playlist was processed (season URL subscriptions, or a
# series whose own artwork is missing), promote a season poster to the
# series poster Jellyfin looks for.
ensure_poster() {
  # plain glob loops, not compgen: the bash behind writeShellApplication is
  # built --disable-progcomp, so the compgen builtin does not exist there
  local p
  for p in "$1"/poster.*; do
    [[ -e "$p" ]] && return 0
  done
  for p in "$1"/season[0-9]*-poster.*; do
    [[ -e "$p" ]] || continue
    cp -- "$p" "$1/poster.${p##*.}"
    break
  done
}

# DR fills the poster slot with a generic play-button placeholder (a fixed
# ImageId) for every show without portrait artwork - most of the children's
# series - and the playlist thumbnail download above then writes that
# placeholder over poster.jpg on every run. The real artwork for those shows
# lives in the square/tile/wallpaper slots, so when the metadata shows the
# poster is the placeholder, overwrite the downloaded file with the best of
# those instead.
placeholder_image="ImageId='16099618'"
fix_placeholder_poster() {
  local json="$1" target="$2" url
  jq -e --arg ph "$placeholder_image" \
    '[.thumbnails[]? | select(.id == "poster") | .url // ""] | first // "" | contains($ph)' \
    "$json" >/dev/null || return 0
  url="$(jq -r --arg ph "$placeholder_image" '
    [.thumbnails[]? | select((.url // "") | contains($ph) | not)] as $t
    | [$t[] | select(.id == "square")] + [$t[] | select(.id == "tile")]
      + [$t[] | select(.id == "wallpaper")]
    | (first | .url) // empty' "$json")"
  [[ -n "$url" ]] || return 0
  # the alternatives are often PNGs; DR's resize service transcodes on
  # request, so ask for jpg to match the .jpg name the file keeps
  url="${url//Format='png'/Format='jpg'}"
  if curl -fsSL -m 30 -o "$target.tmp" "$url"; then
    mv -- "$target.tmp" "$target"
    echo "drtv-dl: replaced placeholder poster: $target"
  else
    rm -f -- "$target.tmp"
    warn "could not replace placeholder poster $target"
  fi
}

while IFS= read -r -d '' f; do
  dir="${f%/*}"
  base="${f%.info.json}"
  case "${base##*/}" in
    tvshow)
      jq -r "$tvshow_nfo" "$f" >"$dir/tvshow.nfo"
      echo "drtv-dl: wrote $dir/tvshow.nfo"
      fix_placeholder_poster "$f" "$dir/poster.jpg"
      ensure_poster "$dir"
      ;;
    season[0-9]*)
      # a season playlist only stands in for the series when nothing has
      # written the series-level files yet
      if [[ ! -e "$dir/tvshow.nfo" ]]; then
        jq -r "$tvshow_nfo" "$f" >"$dir/tvshow.nfo"
        echo "drtv-dl: wrote $dir/tvshow.nfo"
      fi
      fix_placeholder_poster "$f" "$dir/${base##*/}-poster.jpg"
      ensure_poster "$dir"
      ;;
    *)
      # extraction ran (a probe, or a failed download) but there is no
      # video to pair sidecars with - drop them instead of littering
      if ! media_exists "$base"; then
        rm -f -- "$base"-thumb.*
        rm -f -- "$f"
        continue
      fi
      jq -r "$media_nfo" "$f" >"$base.nfo"
      echo "drtv-dl: wrote $base.nfo"
      # films get DR's portrait poster too; episodes carry no poster id
      # and film folders inherit nothing from a series playlist
      poster_url="$(jq -r --arg ph "$placeholder_image" 'if .series then empty
        else ([.thumbnails[]? | select(.id == "poster")
          | .url // "" | select(contains($ph) | not)] | first) // empty
        end' "$f")"
      if [[ -n "$poster_url" && ! -e "$dir/poster.jpg" ]]; then
        curl -fsSL -m 30 -o "$dir/poster.jpg" "$poster_url" || rm -f "$dir/poster.jpg"
      fi
      ;;
  esac
  rm -f -- "$f"
done < <(find "$dest" -name '*.info.json' -type f -print0)

# Repeat everything easy to miss in a long scrollback: what arrived on disk,
# and every warning - the script's own and yt-dlp's - once more at the end.
downloaded=0
if [[ -s "$manifest" ]]; then
  downloaded="$(wc -l <"$manifest")"
fi
issues="$(grep -E '^(WARNING|ERROR):' "$errlog" | sort -u || true)"

# Scratch files an interrupted run (this one or an earlier one) left behind.
# Reported, never removed on the script's own initiative: -c does that, and
# only when asked - a .part-Frag file can belong to a second drtv-dl running
# into the same library right now.
leftover_n=0
leftover_bytes=0
while IFS= read -r -d '' f; do
  leftover_n=$((leftover_n + 1))
  leftover_bytes=$((leftover_bytes + $(stat -c %s "$f" 2>/dev/null || echo 0)))
done < <(find_leftovers)

{
  echo
  echo "drtv-dl: ---- run summary ----"
  if [[ "$scanned" -gt 0 ]]; then
    echo "drtv-dl: $present of $scanned videos were already on disk"
  fi
  echo "drtv-dl: downloaded $downloaded file(s) in $(fmt_duration $(($(date +%s) - started)))"
  if [[ "$downloaded" -gt 0 ]]; then
    sed 's/^/drtv-dl:   /' "$manifest"
  fi
  if [[ "$leftover_n" -gt 0 ]]; then
    echo "drtv-dl: $leftover_n leftover file(s) from interrupted runs, $(fmt_size "$leftover_bytes") - remove with: drtv-dl -d ${dest} -c"
  fi
  if [[ ${#warnings[@]} -gt 0 || -n "$issues" || "$status" -ne 0 ]]; then
    echo "drtv-dl: warnings and errors:"
    for w in "${warnings[@]}"; do
      echo "drtv-dl:   warning: $w"
    done
    if [[ -n "$issues" ]]; then
      while IFS= read -r line; do
        echo "drtv-dl:   yt-dlp: $line"
      done <<<"$issues"
    fi
    if [[ "$status" -ne 0 ]]; then
      echo "drtv-dl:   yt-dlp exited with status $status - some downloads may have failed"
    fi
  else
    echo "drtv-dl: no warnings"
  fi
} >&2

exit "$status"
