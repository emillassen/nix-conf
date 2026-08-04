# Syncs a local, Calibre-style library ("Last, First"/Title/) with
# the free ebooks at standardebooks.org: discovers the published catalog from
# the site's sitemap in one request, then downloads whatever isn't on disk yet in
# all 4 formats the site offers (epub, azw3, kepub, advanced epub) and lifts
# each book's embedded cover out as a cover.jpg alongside the files.
{
  writeShellApplication,
  curl,
  gnugrep,
  gnused,
  unzip,
  findutils,
  coreutils,
}:
writeShellApplication {
  name = "standardebooks-dl";
  runtimeInputs = [
    curl
    gnugrep # -P (PCRE) for pulling links/metadata out of HTML and XML
    gnused
    unzip # reads content.opf and the cover image out of the epub (it's a zip)
    findutils # sweeps the library for the epubs covers and the ledger come from
    coreutils
  ];
  text = builtins.readFile ./standardebooks-dl.sh;
}
