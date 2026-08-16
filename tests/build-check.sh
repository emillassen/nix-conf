#!/usr/bin/env bash
#
# The belt-and-braces check the hermetic suite deliberately leaves out: build
# the two pkgs/ derivations for real and run each one's --help through the
# preamble writeShellApplication actually generates. Those builds are also the
# only place either script is linted at all.
#
# Not part of tests/run.sh: it needs the Nix daemon and a populated store, where
# the suite needs neither. Run it after touching anything under pkgs/.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
out="${TMPDIR:-/tmp}/drtv-se-build-check.$$"
mkdir -p "$out"
trap 'rm -rf "$out"' EXIT

for pkg in drtv-dl standardebooks-dl; do
  echo "== building .#$pkg"
  # -o inside a scratch directory, never in the repo: a result symlink there is
  # a GC root that outlives the check.
  nix build ".#$pkg" -o "$out/$pkg"
  echo "== $pkg --help"
  "$out/$pkg/bin/$pkg" -h >"$out/$pkg.help"
  head -n 1 "$out/$pkg.help"
done

echo "both packages build (shellcheck included) and answer -h"
