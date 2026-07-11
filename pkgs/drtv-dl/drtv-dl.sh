usage() {
  # requested help goes to stdout; usage errors go to stderr
  [[ "${1:-0}" == 0 ]] || exec >&2
  cat <<'EOF'
Usage: drtv-dl [-d DIR] [-l] [-n] [-r] [URL...] [extra yt-dlp options...]

Download one or more DRTV (dr.dk/drtv) series, seasons or films,
named so Jellyfin picks them up:

  Series Name/Season 10/Series Name - S10E05 - Episode Title.ext
  Film Name (1968)/Film Name (1968).ext

Episodes whose file already exists on disk are skipped up front via a cheap
playlist scan (one API request per season) instead of being re-extracted
one webpage at a time on every run.

Jellyfin NFO files and artwork are generated alongside the downloads:
tvshow.nfo, poster and season posters per series, an .nfo and thumb image
per episode, and an .nfo plus poster per film. The NFOs carry
<lockdata>true</lockdata>, so Jellyfin keeps DR's metadata instead of
guessing (often wrongly) via TVDB/TMDB. Episodes skipped by the fast scan
keep whatever sidecars they have; run once with -r to backfill NFOs and
images for a library downloaded before this existed.

With no URLs, they are read from a drtv-series.txt in the library root
(see -d): one series or season URL per line; blank lines, #-comments and
anything after the URL are ignored. Keep one next to your series and
staying current is just:

  cd /mnt/series && drtv-dl -n    # list episodes you don't have yet
  cd /mnt/series && drtv-dl       # download them

Options:
  -d DIR   root of your TV library (default: current directory)
  -l       don't download; print the episode links instead, one per line
           (e.g. drtv-dl -l URL > links.txt)
  -n       don't download; list episodes that are not on disk yet, one per
           line. Series/season URLs only - films and direct episode links
           are skipped in this mode.
  -r       recheck every episode with yt-dlp even if its file exists
           (use if files were renamed and the fast skip misjudges them,
           or to regenerate NFOs and images for existing files)
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
while getopts ":d:lnrh" opt; do
  case "$opt" in
    d) dest="$OPTARG" ;;
    l) links_only=1 ;;
    n) check_only=1 ;;
    r) recheck=1 ;;
    h) usage ;;
    *) usage 1 ;;
  esac
done
shift $((OPTIND - 1))
if [[ "$check_only" == 1 && "$recheck" == 1 ]]; then
  echo "drtv-dl: -n and -r cannot be combined" >&2
  exit 1
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

# yt-dlp's DRTV extractor only matches the canonical slug URLs
# (/drtv/serie/gurli-gris_7190). Bare-ID URLs like /drtv/serie/7190
# redirect there in a browser, so resolve them the same way first.
args=()
playlist_urls=()
for url in "$@"; do
  if [[ "$url" =~ ^https?://(www\.)?dr\.dk/drtv/(serie|saeson)/[0-9]+/?$ ]]; then
    # One GET serves both detection paths: -w appends the post-redirect URL
    # after the body, and the body is kept for the canonical-<link> fallback
    # used when the server answers 200 with the SPA page instead of redirecting.
    page="$(curl -fsSL -w '\n%{url_effective}' "$url" 2>/dev/null)" || page=""
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
      echo "drtv-dl: warning: could not resolve $url to its canonical (slug) form;" \
        "yt-dlp may not recognise it - use the URL from your browser's address bar" >&2
    fi
  fi
  if [[ "$url" =~ ^https?://(www\.)?dr\.dk/drtv/(serie|saeson)/[^/]+_[0-9]+/?$ ]]; then
    playlist_urls+=("$url")
  elif [[ "$check_only" == 1 && "$url" == http* ]]; then
    echo "drtv-dl: -n: skipping $url (not a series/season URL)" >&2
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
outbase="$dest/%(series,movie_name)s/%(season_number&Season {:02d}|)s/%(series&{} - |)s%(season_number&S{:02d}|)s%(episode_number&E{:02d}|)s%(series& - |)s%(movie_name,episode,title)s"
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
skip_args=()
if [[ "$check_only" == 1 && ${#playlist_urls[@]} -eq 0 ]]; then
  echo "drtv-dl: -n: no series or season URLs to check" >&2
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
    if [[ "$check_only" == 0 ]]; then
      archive="$(mktemp)"
      trap 'rm -f "$archive"' EXIT
    fi
    scanned=0
    present=0
    while IFS= read -r id && IFS= read -r name; do
      scanned=$((scanned + 1))
      base="${name%.NA}"
      found=0
      for f in "$base".*; do
        [[ -e "$f" ]] || continue
        # a real download has a single-token extension; leftovers like
        # .part/.ytdl/.f<id>.mp4 from aborted runs must not count as done,
        # and neither do the NFO/image sidecars generated below
        ext="${f#"$base".}"
        [[ "$ext" == *.* ]] && continue
        case "$ext" in nfo | jpg | jpeg | png | webp) continue ;; esac
        found=1
        break
      done
      if [[ "$found" == 1 ]]; then
        present=$((present + 1))
        if [[ "$check_only" == 0 ]]; then
          printf 'drtv %s\n' "$id" >>"$archive"
        fi
      elif [[ "$check_only" == 1 ]]; then
        printf '%s\n' "${base#"$dest/"}"
      fi
    done < <(yt-dlp --ignore-errors --flat-playlist "${meta_args[@]}" \
      --output "$outtmpl" --print id --print filename "${season_urls[@]}" 2>/dev/null || true)
    if [[ "$check_only" == 1 ]]; then
      if [[ "$scanned" -eq 0 ]]; then
        echo "drtv-dl: warning: playlist scan found no episodes" >&2
        exit 1
      fi
      echo "drtv-dl: $((scanned - present)) of $scanned episodes not on disk yet" >&2
      exit 0
    fi
    if [[ "$scanned" -gt 0 ]]; then
      echo "drtv-dl: $present of $scanned episodes already on disk; skipping those" >&2
      skip_args=(--download-archive "$archive")
    else
      echo "drtv-dl: warning: playlist scan found no episodes; checking everything" >&2
    fi
  fi
  if [[ "$check_only" == 1 ]]; then
    # only reached when no season playlist could be scanned at all
    echo "drtv-dl: -n: could not expand the URLs into season playlists" >&2
    exit 1
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
# no exec: the trap above must clean up the throwaway archive, and the NFO
# pass below must still run (yt-dlp's exit status is re-raised at the end)
status=0
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
  --output "pl_thumbnail:$dest/%(series)s/%(season_number&season{:02d}-poster|poster)s.%(ext)s" \
  --output "pl_infojson:$dest/%(series)s/%(season_number&season{:02d}|tvshow)s" \
  "${args[@]}" || status=$?

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
  local p
  if ! compgen -G "$1/poster.*" >/dev/null; then
    for p in "$1"/season[0-9]*-poster.*; do
      [[ -e "$p" ]] || continue
      cp -- "$p" "$1/poster.${p##*.}"
      break
    done
  fi
}

while IFS= read -r -d '' f; do
  dir="${f%/*}"
  base="${f%.info.json}"
  case "${base##*/}" in
    tvshow)
      jq -r "$tvshow_nfo" "$f" >"$dir/tvshow.nfo"
      ensure_poster "$dir"
      ;;
    season[0-9]*)
      # a season playlist only stands in for the series when nothing has
      # written the series-level files yet
      [[ -e "$dir/tvshow.nfo" ]] || jq -r "$tvshow_nfo" "$f" >"$dir/tvshow.nfo"
      ensure_poster "$dir"
      ;;
    *)
      jq -r "$media_nfo" "$f" >"$base.nfo"
      # films get DR's portrait poster too; episodes carry no poster id
      # and film folders inherit nothing from a series playlist
      poster_url="$(jq -r 'if .series then empty
        else ([.thumbnails[]? | select(.id == "poster") | .url] | first) // empty
        end' "$f")"
      if [[ -n "$poster_url" && ! -e "$dir/poster.jpg" ]]; then
        curl -fsSL -o "$dir/poster.jpg" "$poster_url" || rm -f "$dir/poster.jpg"
      fi
      ;;
  esac
  rm -f -- "$f"
done < <(find "$dest" -name '*.info.json' -type f -print0)

exit "$status"
