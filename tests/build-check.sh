#!/usr/bin/env bash
#
# The belt-and-braces check the hermetic suite deliberately leaves out: build
# the pkgs/ script derivations for real and run each one's --help through the
# wrapper its writer actually generates. Those builds are also the only place
# the scripts are linted at all (shellcheck for the two shell ones, flake8 for
# misterzine-jellyfin-update).
#
# Not part of tests/run.sh: it needs the Nix daemon and a populated store, where
# the suite needs neither. Run it after touching anything under pkgs/.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# mktemp, not a pid-named directory: `mkdir -p` happily reuses one that some
# other process made first, symlink and all, and the result links land in it.
out="$(mktemp -d "${TMPDIR:-/tmp}/drtv-se-build-check.XXXXXX")"
trap 'rm -rf "$out"' EXIT

for pkg in drtv-dl standardebooks-dl misterzine-jellyfin-update; do
  echo "== building .#$pkg"
  # -o inside a scratch directory, never in the repo: a result symlink there is
  # a GC root that outlives the check.
  nix build ".#$pkg" -o "$out/$pkg"
  echo "== $pkg --help"
  "$out/$pkg/bin/$pkg" -h >"$out/$pkg.help"
  head -n 1 "$out/$pkg.help"
done

echo "all packages build (shellcheck/flake8 included) and answer -h"
