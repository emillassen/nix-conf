#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl jq nix-prefetch-github gawk

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

echo "Updating src in default.nix..."

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

# Sync the vendored dependency pins to whatever the pinned source commit expects.
# devilutionX declares each 3rdParty dependency in 3rdParty/<dir>/CMakeLists.txt,
# either as an archive URL (fetchzip in default.nix) or a GIT_TAG (fetchFromGitHub).
# update.sh only bumps `src`, so these must be re-synced or the source and its
# vendored deps drift apart and the build breaks (e.g. mpqfs symbol mismatches).

# Map each Nix `let` binding to its 3rdParty directory. Names differ in case
# (sheenbidi/SheenBidi) and separator (unordered-dense/unordered_dense).
ZIP_VARS=(asio libsmackerdec sol2 mpqfs sheenbidi unordered-dense)
ZIP_DIRS=(asio libsmackerdec sol2 mpqfs SheenBidi unordered_dense)
GIT_VARS=(libzt)
GIT_DIRS=(libzt)

raw() { curl -sfL "https://raw.githubusercontent.com/$OWNER/$REPO/$REV/3rdParty/$1/CMakeLists.txt"; }

to_sri() { nix hash convert --hash-algo sha256 --to sri "$1"; }

# Replace url+hash (fetchzip) or rev+hash (fetchFromGitHub) inside one `let` binding.
patch_block() {
  local var="$1" key="$2" val="$3" hash="$4"
  awk -v var="$var" -v key="$key" -v val="$val" -v hash="$hash" '
    $0 ~ "^  " var " = fetch" { inblk = 1 }
    inblk && $0 ~ ("^ *" key " = ") {
      sub(key " = \"[^\"]*\"", key " = \"" val "\"")
    }
    inblk && /hash = / {
      sub(/hash = "[^"]+"/, "hash = \"" hash "\"")
      inblk = 0
    }
    { print }
  ' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
}

echo "Syncing vendored dependency pins..."

for i in "${!ZIP_VARS[@]}"; do
  var="${ZIP_VARS[$i]}"
  dir="${ZIP_DIRS[$i]}"
  cml="$(raw "$dir")"
  url="$(echo "$cml" | grep -oE 'https://[^"[:space:]]+\.tar\.gz' | head -n1)"
  if [ -z "$url" ]; then
    echo "  ! $var: no archive URL found in 3rdParty/$dir/CMakeLists.txt" >&2
    exit 1
  fi
  if grep -qF "$url" "$FILE"; then
    echo "  = $var: unchanged"
    continue
  fi
  echo "  ↻ $var: $url"
  sri="$(to_sri "$(nix-prefetch-url --unpack "$url" 2>/dev/null)")"
  patch_block "$var" url "$url" "$sri"
done

for i in "${!GIT_VARS[@]}"; do
  var="${GIT_VARS[$i]}"
  dir="${GIT_DIRS[$i]}"
  cml="$(raw "$dir")"
  tag="$(echo "$cml" | grep -oE 'GIT_TAG[[:space:]]+[0-9a-fA-F]+' | head -n1 | awk '{print $2}')"
  repo_url="$(echo "$cml" | grep -oE 'GIT_REPOSITORY[[:space:]]+https://github.com/[^[:space:]]+' | head -n1 | awk '{print $2}')"
  if [ -z "$tag" ] || [ -z "$repo_url" ]; then
    echo "  ! $var: no GIT_TAG/GIT_REPOSITORY found in 3rdParty/$dir/CMakeLists.txt" >&2
    exit 1
  fi
  gh_slug="${repo_url#https://github.com/}"
  gh_slug="${gh_slug%.git}"
  gh_owner="${gh_slug%%/*}"
  gh_repo="${gh_slug##*/}"
  if grep -qF "$tag" "$FILE"; then
    echo "  = $var: unchanged"
    continue
  fi
  echo "  ↻ $var: $tag"
  sri="$(nix-prefetch-github --rev "$tag" --fetch-submodules "$gh_owner" "$gh_repo" | jq -r '.hash')"
  patch_block "$var" rev "$tag" "$sri"
done

echo "Done → $VERSION"
