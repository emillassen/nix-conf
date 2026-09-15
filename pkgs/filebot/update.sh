#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl gawk

# Bump pkgs/filebot/default.nix to the latest release published on filebot.net.
#
#   ./update.sh        update default.nix in place
#   ./update.sh -n     report what would change, write nothing
#
# filebot.net is the only publisher — no git repo, no release feed, no API — so
# the version comes from the download link on the front page.

set -euo pipefail

HOMEPAGE="https://www.filebot.net"

FILE="$(dirname "$0")/default.nix"

DRY_RUN=0
case "${1-}" in
"") ;;
-n | --dry-run) DRY_RUN=1 ;;
-h | --help)
  echo "usage: $(basename "$0") [-n|--dry-run]"
  exit 0
  ;;
*)
  echo "usage: $(basename "$0") [-n|--dry-run]" >&2
  exit 2
  ;;
esac

# nix and nix-prefetch-url come from the ambient Nix install rather than the
# nix-shell above, so that this uses the same nix the caller builds with.
for tool in awk curl nix nix-prefetch-url; do
  command -v "$tool" >/dev/null ||
    { echo "error: $tool not found in PATH" >&2; exit 1; }
done

[ -f "$FILE" ] || { echo "error: $FILE not found" >&2; exit 1; }

# awk's sub() gives `&` and `\` special meaning in the replacement text.
escape_repl() {
  local s="${1//\\/\\\\}"
  printf '%s' "${s//&/\\&}"
}

echo "Fetching the current release from $HOMEPAGE..."

PAGE="$(curl -sfL --retry 2 "$HOMEPAGE")" ||
  { echo "error: could not fetch $HOMEPAGE" >&2; exit 1; }

# Read the version off the portable-tarball link specifically, not off any
# FileBot_* string: the .deb/.msi/.pkg links can carry a different version.
VERSION="$(grep -oE 'FileBot_[0-9]+(\.[0-9]+)+-portable\.tar\.xz' <<<"$PAGE" |
  head -n1 | sed -E 's/^FileBot_//; s/-portable\.tar\.xz$//')"

if [ -z "$VERSION" ]; then
  echo "error: no portable tarball link found on $HOMEPAGE" >&2
  exit 1
fi

CURRENT="$(awk 'match($0, /^  version = "([^"]+)"/, a) { print a[1]; exit }' "$FILE")"
if [ -z "$CURRENT" ]; then
  echo "error: could not find the pinned version in $FILE" >&2
  exit 1
fi

if [ "$VERSION" = "$CURRENT" ]; then
  echo "  = already at $VERSION"
  exit 0
fi

# A rollback or a cached page is not an update: writing it would downgrade the
# system on the next rebuild.
if [ "$(printf '%s\n%s\n' "$VERSION" "$CURRENT" | sort -V | tail -n1)" = "$CURRENT" ]; then
  echo "error: $HOMEPAGE offers $VERSION, older than the pinned $CURRENT" >&2
  exit 1
fi

URL="https://get.filebot.net/filebot/FileBot_${VERSION}/FileBot_${VERSION}-portable.tar.xz"

echo "  ↻ $CURRENT → $VERSION"
echo "       $URL"

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo "1 change available (dry run, $FILE not written)."
  exit 0
fi

echo "Prefetching nix hash..."
if ! B32="$(nix-prefetch-url "$URL" 2>/dev/null)" || [ -z "$B32" ]; then
  echo "error: failed to prefetch $URL" >&2
  exit 1
fi
HASH="$(nix hash convert --hash-algo sha256 --to sri "$B32")"
echo "       hash: $HASH"

# Written to a scratch copy first, so a failure leaves the tree untouched.
WORK="$(mktemp -t filebot-default.XXXXXX.nix)"
trap 'rm -f "$WORK"' EXIT

awk -v version="$(escape_repl "$VERSION")" -v hash="$(escape_repl "$HASH")" '
  /^  version = "/ {
    sub(/version = "[^"]*"/, "version = \"" version "\"")
    seen_version = 1
  }
  /^  hash = "/ {
    sub(/hash = "[^"]*"/, "hash = \"" hash "\"")
    seen_hash = 1
  }
  { print }
  END {
    if (!seen_version || !seen_hash)
      exit 1
  }
' "$FILE" >"$WORK" ||
  { echo "error: could not locate version/hash in $FILE" >&2; exit 1; }

if cmp -s "$WORK" "$FILE"; then
  echo "error: expected a change but $FILE is byte-identical" >&2
  exit 1
fi

cp "$WORK" "$FILE"

echo
echo "Updated $FILE → $VERSION"
