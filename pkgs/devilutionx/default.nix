{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchzip,
  makeWrapper,
  bzip2,
  cmake,
  gettext,
  libpng,
  libsodium,
  libtiff,
  libwebp,
  lua5_4,
  magic-enum,
  pkg-config,
  SDL2,
  SDL2_image,
  SDL_audiolib,
  fmt,
  smpq,
}:

let
  asio = fetchzip {
    url = "https://github.com/diasurgical/asio/archive/4bcf552fcea3e1ae555dde2ab33bc9fa6770da4d.tar.gz";
    hash = "sha256-MhCPqe7YyoPWLpTu55UWNM1bmOX3TNL24FFSsBIohCM=";
  };

  libsmackerdec = fetchzip {
    url = "https://github.com/diasurgical/libsmackerdec/archive/0aaaf8c94a097b009d844db0d44dd7cd0ff81922.tar.gz";
    hash = "sha256-5p63U3fpU2mh1UTYk/dKwG4Lt2aG2oDXPTpehvbszjw=";
  };

  libzt = fetchFromGitHub {
    owner = "diasurgical";
    repo = "libzt";
    rev = "1a9d83b8c4c2bdcd7ea6d8ab1dd2771b16eb4e13";
    fetchSubmodules = true;
    hash = "sha256-/A77ZM4s+br1hYa0OBdjXcWXUXYG+GiEYcW8VB+UJHo=";
  };

  sol2 = fetchzip {
    url = "https://github.com/diasurgical/sol2/archive/832ac772c2cd3d9620d447e9e77897f7b5e806e3.tar.gz";
    hash = "sha256-CF+8bYujjPu/OP3dt3TvaWz3rnJDfCKB/UjgO6u81GI=";
  };

  mpqfs = fetchzip {
    url = "https://github.com/diasurgical/mpqfs/archive/9423bd48d04c8a0c51d3df6ce328e66785e3b441.tar.gz";
    hash = "sha256-YkfXKtJVmUOM6Cvmjatmn67bBL7sMmj7gr8BFal+ePc=";
  };

  sheenbidi = fetchzip {
    url = "https://github.com/Tehreer/SheenBidi/archive/refs/tags/v2.9.0.tar.gz";
    hash = "sha256-d4JttBe0aPZdihnMpmLUo9NuF7LUeZoeWZ3ItjMNwx8=";
  };

  unordered-dense = fetchzip {
    url = "https://github.com/martinus/unordered_dense/archive/refs/tags/v4.4.0.tar.gz";
    hash = "sha256-tCsfPOPz7AFqV7HOumtE3WwwOwLckjYd+9PA5uLlhpE=";
  };

in

stdenv.mkDerivation {
  pname = "devilutionx";
  version = "1.6.0-unstable-2026-04-03";

  src = fetchFromGitHub {
    owner = "diasurgical";
    repo = "devilutionX";
    rev = "005e7dcc233cc9734831ef4d37da2a7270da1584";
    hash = "sha256-XPM7mTpiEop3HK7YoLi5JYUjki1ga3b4unnxqgslUR8=";
  };

  postPatch = ''
    substituteInPlace Source/engine/assets.cpp --replace-fail \
      'paths.emplace_back("/usr/share/diasurgical/devilutionx/");' \
      'paths.emplace_back("/usr/share/diasurgical/devilutionx/"); paths.emplace_back("'"$out"'/share/diasurgical/devilutionx/");'
  '';

  cmakeFlags = [
    "-DFETCHCONTENT_SOURCE_DIR_ASIO=${asio}"
    "-DFETCHCONTENT_SOURCE_DIR_LIBSMACKERDEC=${libsmackerdec}"
    "-DFETCHCONTENT_SOURCE_DIR_LIBZT=${libzt}"
    "-DFETCHCONTENT_SOURCE_DIR_MPQFS=${mpqfs}"
    "-DFETCHCONTENT_SOURCE_DIR_SHEENBIDI=${sheenbidi}"
    "-DFETCHCONTENT_SOURCE_DIR_SOL2=${sol2}"
    "-DFETCHCONTENT_SOURCE_DIR_UNORDERED_DENSE=${unordered-dense}"
    "-DBUILD_TESTING=OFF"
  ];

  nativeBuildInputs = [
    cmake
    gettext
    makeWrapper
    pkg-config
    smpq
  ];

  buildInputs = [
    SDL2
    SDL2_image
    SDL_audiolib
    bzip2
    fmt
    libpng
    libsodium
    libtiff
    libwebp
    lua5_4
    magic-enum
  ];

  postFixup = ''
    wrapProgram $out/bin/devilutionx \
      --prefix XDG_DATA_DIRS : $out/share
  '';

  meta = {
    homepage = "https://github.com/diasurgical/devilutionX";
    description = "Diablo build for modern operating systems";
    license = lib.licenses.sustainableUse;
    mainProgram = "devilutionx";
    maintainers = [ ];
    platforms = lib.platforms.linux;
  };
}
