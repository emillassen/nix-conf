usage() {
  cat <<'EOF'
Usage: drtv-dl [-d DIR] [-l] URL [extra yt-dlp options...]

Download every episode of a DRTV (dr.dk/drtv) series or season, named so
Jellyfin picks them up:

  Series Name/Season 10/Series Name - S10E05 - Episode Title.mkv

Options:
  -d DIR   root of your TV library (default: current directory)
  -l       don't download; print the episode links instead, one per line
           (e.g. drtv-dl -l URL > links.txt)
  -h       show this help

Anything after the URL is passed straight to yt-dlp.
EOF
  exit "${1:-0}"
}

dest="."
links_only=0
while getopts ":d:lh" opt; do
  case "$opt" in
    d) dest="$OPTARG" ;;
    l) links_only=1 ;;
    h) usage ;;
    *) usage 1 ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -ge 1 ]] || usage 1
url="$1"
shift

# yt-dlp's DRTV extractor only matches the canonical slug URLs
# (/drtv/serie/gurli-gris_7190). Bare-ID URLs like /drtv/serie/7190
# redirect there in a browser, so resolve them the same way first.
if [[ "$url" =~ ^https?://(www\.)?dr\.dk/drtv/(serie|saeson)/[0-9]+/?$ ]]; then
  resolved="$(curl -fsSL -o /dev/null -w '%{url_effective}' "$url" 2>/dev/null)" || resolved=""
  if [[ ! "$resolved" =~ _[0-9]+/?$ ]]; then
    page="$(curl -fsSL "$url" 2>/dev/null)" || page=""
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

if [[ "$links_only" == 1 ]]; then
  exec yt-dlp --flat-playlist --print webpage_url "$url" "$@"
fi

# DRTV episode titles repeat the series name ("Gurli Gris: Slemme skildpadde");
# strip that prefix from episode/title, but only when it matches the series
# exactly (the backreference), so unrelated colons in titles are left alone.
exec yt-dlp \
  --embed-metadata \
  --sub-langs all --embed-subs \
  --concurrent-fragments 6 \
  --parse-metadata '%(series)s|%(episode)s:^(?P<series>.+)\|(?P=series): (?P<episode>.+)$' \
  --parse-metadata '%(series)s|%(title)s:^(?P<series>.+)\|(?P=series): (?P<title>.+)$' \
  --output "$dest/%(series)s/Season %(season_number)02d/%(series)s - S%(season_number)02dE%(episode_number)02d - %(episode)s.%(ext)s" \
  "$url" "$@"
