# shellcheck shell=bash
# Helpers for the drtv-dl cases: a library directory and the recorded scenario
# the yt-dlp stub answers from.
#
# A scenario is built up a piece at a time and written once:
#
#   drtv_init
#   drtv_meta   "$serie" '{"series":"Gurli Gris"}'
#   drtv_child  "$serie" "$season"
#   drtv_video  "$ep1"   '{"id":"1001","ext":"mp4", ...}'
#   drtv_write

DRTV_LIB=""
DRTV_SCEN=""

drtv_init() {
  use_stubs yt-dlp curl
  DRTV_LIB="$TMP/library"
  DRTV_SCEN="$TMP/scenario.json"
  # A case may set up more than one scenario; each starts from an empty library
  # and from empty stub logs. The logs matter as much as the library: they are
  # where "how many extractions did that cost" is read from, and a count taken
  # after the second scenario would otherwise quietly include the first one's
  # calls. The curl stub's per-URL consume counters live here too, and a new
  # scenario redeclares its URLs, so those have to go with them.
  rm -rf "$DRTV_LIB"
  mkdir -p "$DRTV_LIB"
  rm -f "$STUBLOG"/*
  export YTDLP_SCENARIO="$DRTV_SCEN"
  export CURL_MAP="$TMP/curl-map"
  : >"$CURL_MAP"
  printf '{"playlists":{},"playlist_meta":{},"videos":{}}\n' >"$DRTV_SCEN"
}

_scen_apply() {
  local tmp="$DRTV_SCEN.tmp"
  jq "$@" "$DRTV_SCEN" >"$tmp" && mv -- "$tmp" "$DRTV_SCEN"
}

drtv_meta() { _scen_apply --arg u "$1" --argjson v "$2" '.playlist_meta[$u] = $v'; }
drtv_video() { _scen_apply --arg u "$1" --argjson v "$2" '.videos[$u] = $v'; }
drtv_child() {
  _scen_apply --arg p "$1" --arg c "$2" \
    '.playlists[$p] = ((.playlists[$p] // []) + [$c])'
}
# A playlist that exists but is empty — a season DR has taken down, say.
drtv_playlist() { _scen_apply --arg p "$1" '.playlists[$p] = (.playlists[$p] // [])'; }

drtv_write() { :; } # the scenario is written as it is built; here for symmetry

run_drtv() { run_fragment "$DRTVDL" "$@"; }

# The events the yt-dlp stub recorded: "extract", "skip-pre" (matched in the
# download archive against the URL slug, before any extraction) or "skip-post".
drtv_events() { cat "$STUBLOG/ytdlp-events.log" 2>/dev/null || true; }
drtv_extractions() {
  awk '/^extract /{ n++ } END { print n + 0 }' "$STUBLOG/ytdlp-events.log" 2>/dev/null || echo 0
}
