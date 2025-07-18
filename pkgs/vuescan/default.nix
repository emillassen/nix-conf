# Based on https://github.com/NixOS/nixpkgs/issues/217996#issuecomment-1476011005
{
  lib,
  stdenv,
  fetchurl,
  gnutar,
  autoPatchelfHook,
  glibc,
  gtk3,
  xorg,
  libgudev,
  makeDesktopItem,
}:

let
  pname = "vuescan";
  version = "9.8.46.14";
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
stdenv.mkDerivation {
  name = "${pname}-${version}";

  src = fetchurl {
    url = "https://www.hamrick.com/files/vuex6498.tgz";
    hash = "sha256-xotXmNkAkxy4KCgQ2AeGWMo9dJorTiik+k5JO/tmu/8=";
  };

  # Stripping breaks the program
  dontStrip = true;

  nativeBuildInputs = [
    gnutar
    autoPatchelfHook
  ];

  buildInputs = [
    glibc
    gtk3
    xorg.libSM
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

  meta = with lib; {
    description = "A computer program for image scanning, especially of photographs, including negatives.";
    homepage = "https://www.hamrick.com/";
    license = licenses.unfree;
    maintainers = with maintainers; [ Hamrick ];
    platforms = [ "x86_64-linux" ];
  };
}
