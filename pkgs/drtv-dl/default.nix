# Wrapper around yt-dlp that downloads DRTV series/seasons/films with
# Jellyfin-friendly names (Series/Season 01/Series - S01E01 - Title.ext,
# films as Film (Year)/Film (Year).ext) plus Jellyfin NFO files and artwork.
{
  writeShellApplication,
  yt-dlp,
  ffmpeg,
  curl,
  gnugrep,
  jq,
  coreutils,
  findutils,
  gnused,
}:
let
  # DRTV episode pages no longer embed the season/show object, so the episode
  # extractor alone yields series/season_number = NA and the output template
  # produces "NA/Season NA/...". The season playlist has the data; the patch
  # makes it propagate to each episode (url -> url_transparent). It also
  # surfaces show descriptions and poster images the API already returns,
  # which the NFO/artwork generation in the script feeds on.
  yt-dlp' = yt-dlp.overridePythonAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./fix-drtv-season-metadata.patch ];
  });
in
writeShellApplication {
  name = "drtv-dl";
  runtimeInputs = [
    yt-dlp'
    ffmpeg # needed for --embed-metadata / --embed-subs
    curl # resolves bare-ID URLs to their canonical slug form; film posters
    gnugrep
    jq # info.json -> Jellyfin NFO conversion
    coreutils # mktemp, tee, sort, wc, cp, ...
    findutils # the info.json sweeps
    gnused # summary indentation
  ];
  text = builtins.readFile ./drtv-dl.sh;
}
