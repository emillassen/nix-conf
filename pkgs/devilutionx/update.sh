#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl jq nix-prefetch-github

set -euo pipefail

OWNER="diasurgical"
REPO="devilutionX"
BRANCH="master"

FILE="$(dirname "$0")/default.nix"

echo "Fetching latest commit from $OWNER/$REPO ($BRANCH)..."

LATEST=$(curl -sfL "https://api.github.com/repos/$OWNER/$REPO/commits/$BRANCH")

REV=$(echo "$LATEST" | jq -r '.sha')
DATE=$(echo "$LATEST" | jq -r '.commit.author.date' | cut -dT -f1)

VERSION="unstable-${DATE}-${REV:0:7}"

echo "Latest:"
echo "  rev: $REV"
echo "  date: $DATE"
echo "  version: $VERSION"

echo "Prefetching nix hash..."

HASH=$(nix-prefetch-github --rev "$REV" "$OWNER" "$REPO" | jq -r '.hash')

echo "hash: $HASH"

echo "Updating default.nix..."

awk -v rev="$REV" -v hash="$HASH" -v version="$VERSION" '
  BEGIN { in_src = 0 }

  # Replace version anywhere
  /version = / {
    sub(/version = "[^"]+"/, "version = \"" version "\"")
  }

  # Detect start of the src fetch block only
  /src = fetchFromGitHub/ { in_src = 1 }

  # Replace rev inside src fetch block
  in_src && /rev = / {
    sub(/rev = "[^"]+"/, "rev = \"" rev "\"")
  }

  # Replace hash inside src fetch block and end block
  in_src && /hash = / {
    sub(/hash = "[^"]+"/, "hash = \"" hash "\"")
    in_src = 0
  }

  { print }
' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

echo "Done → $VERSION"
