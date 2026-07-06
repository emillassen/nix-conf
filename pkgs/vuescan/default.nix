# Based on https://github.com/NixOS/nixpkgs/issues/217996#issuecomment-1476011005
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  glibc,
  gtk3,
  libsm,
  libgudev,
  makeDesktopItem,
}:

let
  desktopItem = makeDesktopItem {
    name = "VueScan";
    desktopName = "VueScan";
    genericName = "Scanning Program";
    comment = "Scanning Program";
    icon = "vuescan";
    terminal = false;
    type = "Application";
    startupNotify = true;
    categories = [
      "Graphics"
      "Utility"
    ];
    keywords = [
      "scan"
      "scanner"
    ];

    exec = "vuescan";
  };
in
stdenv.mkDerivation rec {
  pname = "vuescan";
  version = "9.8.49.25";

  src = fetchurl {
    url = "https://github.com/emillassen/binary-mirror/releases/download/vuex64-${version}/vuex64-${version}.tgz";
    hash = "sha256-4Z3GqDCZZ1cCeh6WMl0S13rM72szebyuormiCN49dm8=";
  };

  # Stripping breaks the program
  dontStrip = true;

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [
    glibc
    gtk3
    libsm
    libgudev
  ];

  sourceRoot = "VueScan";

  installPhase = ''
    install -m755 -D vuescan $out/bin/vuescan

    mkdir -p $out/share/icons/hicolor/scalable/apps/
    cp vuescan.svg $out/share/icons/hicolor/scalable/apps/vuescan.svg

    mkdir -p $out/lib/udev/rules.d/
    cp vuescan.rul $out/lib/udev/rules.d/60-vuescan.rules

    mkdir -p $out/share/applications/
    ln -s ${desktopItem}/share/applications/* $out/share/applications
  '';

  meta = {
    description = "Program for image scanning, especially of photographs, including negatives";
    homepage = "https://www.hamrick.com/";
    license = lib.licenses.unfree;
    mainProgram = "vuescan";
    maintainers = [
      {
        name = "Emil Lassen";
        github = "emillassen";
      }
    ];
    platforms = [ "x86_64-linux" ];
  };
}
