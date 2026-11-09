# Keeps MisterZine Jellyfin (a Jellyfin client for MiSTer FPGA,
# github.com/matijaerceg/misterzine-jellyfin) up to date on the MiSTer: builds
# the app from each release's public source, which has no supporter-code gate,
# packages it with that release's own FPGA core, jfplay and ffmpeg, and
# installs it over SSH. The hourly timer is in home-manager/config/misterzine.nix.
{
  lib,
  writers,
  bash,
  coreutils,
  git,
  libnotify,
  nix,
  openssh,
}:
writers.writePython3Bin "misterzine-jellyfin-update" {
  # flake8 runs at build time, as shellcheck does for the shell packages. The
  # long lines are messages and command lines, which read worse wrapped.
  flakeIgnore = [ "E501" ];
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [
      bash # --card-dir runs the MiSTer-side steps locally through bash
      coreutils # ... and their rm/mkdir/cat
      git # the source checkout
      libnotify # notify-send, for what the timer did
      nix # nix shell nixpkgs#go_1_XX: the Go the release's go.mod asks for
      openssh # ssh, ssh-keygen
    ])
  ];
} (builtins.readFile ./misterzine-jellyfin-update.py)
