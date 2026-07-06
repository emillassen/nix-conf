# Wrapper around yt-dlp that downloads DRTV series/seasons with
# Jellyfin-friendly names (Series/Season 01/Series S01E01 - Title.ext).
{
  writeShellApplication,
  yt-dlp,
  ffmpeg,
  curl,
  gnugrep,
}:
writeShellApplication {
  name = "drtv-dl";
  runtimeInputs = [
    yt-dlp
    ffmpeg # needed for --embed-metadata / --embed-subs
    curl # resolves bare-ID URLs to their canonical slug form
    gnugrep
  ];
  text = builtins.readFile ./drtv-dl.sh;
}
