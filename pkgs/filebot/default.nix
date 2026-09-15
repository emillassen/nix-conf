# FileBot pinned to the latest upstream release: nixpkgs lags badly (5.2.1 there
# against 5.3.0 upstream, and NixOS/nixpkgs#533518 for 5.2.3 has been open since
# June). Only version/src are ours — every release is the same portable tarball,
# so the rest of nixpkgs' derivation still applies. `./update.sh` rewrites the pin.
#
# Upstream ships no .desktop file or icon, so the GUI (which is what `filebot`
# with no arguments starts) is otherwise terminal-only; hence the launcher below.
{
  lib,
  filebot,
  fetchurl,
  makeDesktopItem,
  unzip,
}:

let
  version = "5.3.0";
  hash = "sha256-Yz15ipF2BwUbT2G+N7WtkjRXBQcIx+fuqZwJlXWDtXU=";

  # One arch-independent archive: lib/Linux-x86_64 and lib/Linux-aarch64 both.
  src = fetchurl {
    url = "https://get.filebot.net/filebot/FileBot_${version}/FileBot_${version}-portable.tar.xz";
    inherit hash;
  };

  # Should nixpkgs overtake the pin, use nixpkgs'. src has to be overridden
  # alongside version, not derived from it: nixpkgs builds its URL out of
  # finalAttrs.version, pointing at a web.archive.org snapshot only 5.2.1 has.
  base =
    if lib.versionOlder filebot.version version then
      filebot.overrideAttrs (_: {
        inherit version src;
      })
    else
      filebot;

in
base.overrideAttrs (
  oldAttrs:
  let
    desktopItem = makeDesktopItem {
      name = "filebot";
      desktopName = "FileBot";
      genericName = "Media File Renamer";
      comment = oldAttrs.meta.description;
      exec = "filebot %U";
      icon = "filebot";
      categories = [
        "AudioVideo"
        "Utility"
      ];
      # Swing derives WM_CLASS from the main class, so the running window is
      # net-filebot-Main; without this KDE won't match it to this launcher.
      startupWMClass = "net-filebot-Main";
    };
  in
  {
    nativeBuildInputs = oldAttrs.nativeBuildInputs or [ ] ++ [ unzip ];

    # installPhase is a bare string that never calls `runHook postInstall`, so
    # a postInstall (or the copyDesktopItems hook) would be silently dropped.
    installPhase = oldAttrs.installPhase + ''
      for icon in 16:window.icon16 32:window.icon16@2x 64:window.icon64 128:window.icon64@2x; do
        size=''${icon%%:*}
        dir="$out/share/icons/hicolor/''${size}x''${size}/apps"
        mkdir -p "$dir"
        # filebot.jar has junk before the zip header, so unzip always exits 1
        # with a warning — check the extracted file instead of the status.
        unzip -p "$out/opt/jar/filebot.jar" "net/filebot/resources/''${icon#*:}.png" > "$dir/filebot.png" || true
        [ -s "$dir/filebot.png" ]
      done

      mkdir -p $out/share
      cp -r ${desktopItem}/share/applications $out/share/
    '';
  }
)
