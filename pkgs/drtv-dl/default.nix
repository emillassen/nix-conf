# Wrapper around yt-dlp that downloads DRTV series/seasons with
# Jellyfin-friendly names (Series/Season 01/Series - S01E01 - Title.ext).
{
  writeShellApplication,
  yt-dlp,
  ffmpeg,
  curl,
  gnugrep,
}:
let
  # DRTV episode pages no longer embed the season/show object, so the episode
  # extractor alone yields series/season_number = NA and the output template
  # produces "NA/Season NA/...". The season playlist has the data; the patch
  # makes it propagate to each episode (url -> url_transparent).
  yt-dlp' = yt-dlp.overridePythonAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./fix-drtv-season-metadata.patch ];
  });
in
writeShellApplication {
  name = "drtv-dl";
  runtimeInputs = [
    yt-dlp'
    ffmpeg # needed for --embed-metadata / --embed-subs
    curl # resolves bare-ID URLs to their canonical slug form
    gnugrep
  ];
  text = builtins.readFile ./drtv-dl.sh;
}
