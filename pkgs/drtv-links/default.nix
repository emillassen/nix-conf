# Scrapes all episode links of a DRTV series/season into a text file,
# one URL per line, ready for `yt-dlp -a FILE`.
{ writers }:
writers.writePython3Bin "drtv-links" {
  flakeIgnore = [ "E501" ];
} (builtins.readFile ./drtv-links.py)
