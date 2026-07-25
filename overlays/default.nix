# This file defines overlays
{ inputs, ... }:
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://wiki.nixos.org/wiki/Overlays
  modifications = _final: prev: {
    # Upstream's portable tarball ships no .desktop file or icon, so the GUI
    # (which is what `filebot` with no arguments starts) is only reachable from
    # a terminal. Lift the app icons out of filebot.jar and add a launcher.
    filebot = prev.filebot.overrideAttrs (
      oldAttrs:
      let
        desktopItem = prev.makeDesktopItem {
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
        nativeBuildInputs = oldAttrs.nativeBuildInputs or [ ] ++ [ prev.unzip ];

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
    );
  };

  # When applied, the stable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.stable'
  stable-packages = final: _prev: {
    stable = import inputs.nixpkgs-stable {
      # pass the plain system string — handing unstable's elaborated
      # hostPlatform to a different nixpkgs version (as localSystem) makes its
      # stdenv bootstrap think it's cross-compiling → infinite recursion
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  };
}
