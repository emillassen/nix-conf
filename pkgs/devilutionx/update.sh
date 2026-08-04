#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl jq nix-prefetch-github gawk

# Bump pkgs/devilutionx/default.nix to the latest upstream master commit, and
# re-sync the vendored dependency pins that commit expects.
#
#   ./update.sh        update default.nix in place
#   ./update.sh -n     report what would change, write nothing
#
# Set GITHUB_TOKEN to lift the unauthenticated API rate limit (60 req/h).

set -euo pipefail

OWNER="diasurgical"
REPO="devilutionX"
BRANCH="master"

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
for tool in awk curl jq nix nix-prefetch-github nix-prefetch-url; do
  command -v "$tool" >/dev/null ||
    { echo "error: $tool not found in PATH" >&2; exit 1; }
done

[ -f "$FILE" ] || { echo "error: $FILE not found" >&2; exit 1; }

# All edits are applied to a scratch copy and only installed over default.nix
# once every fetch has succeeded, so a failure mid-run leaves the tree untouched.
WORK="$(mktemp -t devilutionx-default.XXXXXX.nix)"
trap 'rm -f "$WORK" "$WORK.tmp"' EXIT
cp "$FILE" "$WORK"

CHANGES=()

# awk's sub() gives `&` and `\` special meaning in the replacement text.
escape_repl() {
  local s="${1//\\/\\\\}"
  printf '%s' "${s//&/\\&}"
}

gh_api() {
  if [ -n "${GITHUB_TOKEN-}" ]; then
    curl -sfL -H "Authorization: Bearer $GITHUB_TOKEN" "$1"
  else
    curl -sfL "$1"
  fi
}

require_value() {
  local what="$1" val="$2"
  if [ -z "$val" ] || [ "$val" = "null" ]; then
    echo "error: could not determine $what" >&2
    exit 1
  fi
}

echo "Fetching latest commit from $OWNER/$REPO ($BRANCH)..."

LATEST="$(gh_api "https://api.github.com/repos/$OWNER/$REPO/commits/$BRANCH")" ||
  { echo "error: GitHub API request failed (rate limited? set GITHUB_TOKEN)" >&2; exit 1; }

REV="$(jq -r '.sha // empty' <<<"$LATEST")"
DATE="$(jq -r '.commit.author.date // empty' <<<"$LATEST" | cut -dT -f1)"
SUBJECT="$(jq -r '.commit.message // empty' <<<"$LATEST" | head -n1)"
require_value "the latest commit sha" "$REV"
require_value "the latest commit date" "$DATE"

VERSION="unstable-${DATE}-${REV:0:7}"

CURRENT_REV="$(awk '
  /^  src = fetchFromGitHub/ { in_src = 1 }
  in_src && match($0, /rev = "([^"]+)"/, a) { print a[1]; exit }
' "$WORK")"
require_value "the currently pinned rev in $FILE" "$CURRENT_REV"

if [ "$REV" = "$CURRENT_REV" ]; then
  echo "  = src: already at $VERSION"
else
  echo "  ↻ src: ${CURRENT_REV:0:7} → ${REV:0:7} ($DATE)"
  [ -n "$SUBJECT" ] && echo "       $SUBJECT"
  if [ "$DRY_RUN" -eq 1 ]; then
    CHANGES+=("src → $VERSION")
  else
    echo "Prefetching nix hash..."
    HASH="$(nix-prefetch-github --rev "$REV" "$OWNER" "$REPO" | jq -r '.hash // empty')"
    require_value "the source hash for $REV" "$HASH"
    echo "       hash: $HASH"

    awk -v rev="$(escape_repl "$REV")" \
      -v hash="$(escape_repl "$HASH")" \
      -v version="$(escape_repl "$VERSION")" '
      /^  version = "/ {
        sub(/version = "[^"]*"/, "version = \"" version "\"")
        seen_version = 1
      }
      /^  src = fetchFromGitHub/ { in_src = 1 }
      in_src && /rev = "/ {
        sub(/rev = "[^"]*"/, "rev = \"" rev "\"")
        seen_rev = 1
      }
      in_src && /hash = "/ {
        sub(/hash = "[^"]*"/, "hash = \"" hash "\"")
        seen_hash = 1
        in_src = 0
      }
      { print }
      END {
        if (!seen_version || !seen_rev || !seen_hash)
          exit 1
      }
    ' "$WORK" >"$WORK.tmp" ||
      { echo "error: could not locate version/rev/hash in $FILE" >&2; exit 1; }
    mv "$WORK.tmp" "$WORK"
    CHANGES+=("src → $VERSION")
  fi
fi

# Sync the vendored dependency pins to whatever the pinned source commit expects.
# devilutionX declares each 3rdParty dependency in 3rdParty/<dir>/CMakeLists.txt,
# either as an archive URL (fetchzip in default.nix) or a GIT_TAG (fetchFromGitHub).
# Bumping `src` alone would let the source and its vendored deps drift apart and
# break the build (e.g. mpqfs symbol mismatches), so they are re-checked every run
# — including when `src` is unchanged, which repairs a previously interrupted run.

# Map each Nix `let` binding to its 3rdParty directory. Names differ in case
# (sheenbidi/SheenBidi) and separator (unordered-dense/unordered_dense).
ZIP_VARS=(asio libsmackerdec sol2 mpqfs sheenbidi unordered-dense)
ZIP_DIRS=(asio libsmackerdec sol2 mpqfs SheenBidi unordered_dense)
GIT_VARS=(libzt)
GIT_DIRS=(libzt)

raw() {
  curl -sfL "https://raw.githubusercontent.com/$OWNER/$REPO/$REV/3rdParty/$1/CMakeLists.txt" ||
    { echo "error: could not fetch 3rdParty/$1/CMakeLists.txt at ${REV:0:7}" >&2; exit 1; }
}

to_sri() { nix hash convert --hash-algo sha256 --to sri "$1"; }

# Replace url+hash (fetchzip) or rev+hash (fetchFromGitHub) inside one `let` binding.
patch_block() {
  local var="$1" key="$2" val="$3" hash="$4"
  awk -v var="$var" -v key="$key" \
    -v val="$(escape_repl "$val")" -v hash="$(escape_repl "$hash")" '
    $0 ~ "^  " var " = fetch" { inblk = 1 }
    inblk && $0 ~ ("^ *" key " = \"") {
      sub(key " = \"[^\"]*\"", key " = \"" val "\"")
      seen_key = 1
    }
    inblk && /hash = "/ {
      sub(/hash = "[^"]+"/, "hash = \"" hash "\"")
      seen_hash = 1
      inblk = 0
    }
    { print }
    END {
      if (!seen_key || !seen_hash)
        exit 1
    }
  ' "$WORK" >"$WORK.tmp" ||
    { echo "error: could not locate the $var block in $FILE" >&2; exit 1; }
  mv "$WORK.tmp" "$WORK"
}

echo "Syncing vendored dependency pins..."

for i in "${!ZIP_VARS[@]}"; do
  var="${ZIP_VARS[$i]}"
  dir="${ZIP_DIRS[$i]}"
  cml="$(raw "$dir")"
  url="$(grep -oE 'https://[^"[:space:]]+\.tar\.gz' <<<"$cml" | head -n1)"
  if [ -z "$url" ]; then
    echo "  ! $var: no archive URL found in 3rdParty/$dir/CMakeLists.txt" >&2
    exit 1
  fi
  if grep -qF "\"$url\"" "$WORK"; then
    echo "  = $var: unchanged"
    continue
  fi
  echo "  ↻ $var: $url"
  CHANGES+=("$var → $url")
  [ "$DRY_RUN" -eq 1 ] && continue
  if ! b32="$(nix-prefetch-url --unpack "$url" 2>/dev/null)" || [ -z "$b32" ]; then
    echo "  ! $var: failed to prefetch $url" >&2
    exit 1
  fi
  patch_block "$var" url "$url" "$(to_sri "$b32")"
done

for i in "${!GIT_VARS[@]}"; do
  var="${GIT_VARS[$i]}"
  dir="${GIT_DIRS[$i]}"
  cml="$(raw "$dir")"
  tag="$(grep -oE 'GIT_TAG[[:space:]]+[0-9a-fA-F]+' <<<"$cml" | head -n1 | awk '{print $2}')"
  repo_url="$(grep -oE 'GIT_REPOSITORY[[:space:]]+https://github.com/[^[:space:]]+' <<<"$cml" | head -n1 | awk '{print $2}')"
  if [ -z "$tag" ] || [ -z "$repo_url" ]; then
    echo "  ! $var: no GIT_TAG/GIT_REPOSITORY found in 3rdParty/$dir/CMakeLists.txt" >&2
    exit 1
  fi
  gh_slug="${repo_url#https://github.com/}"
  gh_slug="${gh_slug%.git}"
  gh_owner="${gh_slug%%/*}"
  gh_repo="${gh_slug##*/}"
  if grep -qF "\"$tag\"" "$WORK"; then
    echo "  = $var: unchanged"
    continue
  fi
  echo "  ↻ $var: $tag"
  CHANGES+=("$var → ${tag:0:7}")
  [ "$DRY_RUN" -eq 1 ] && continue
  sri="$(nix-prefetch-github --rev "$tag" --fetch-submodules "$gh_owner" "$gh_repo" | jq -r '.hash // empty')"
  require_value "the $var hash for $tag" "$sri"
  patch_block "$var" rev "$tag" "$sri"
done

echo

if [ "${#CHANGES[@]}" -eq 0 ]; then
  echo "No changes — already up to date at $VERSION."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "${#CHANGES[@]} change(s) available (dry run, $FILE not written):"
  printf '  %s\n' "${CHANGES[@]}"
  exit 0
fi

if cmp -s "$WORK" "$FILE"; then
  echo "error: expected ${#CHANGES[@]} change(s) but $FILE is byte-identical" >&2
  exit 1
fi

cp "$WORK" "$FILE"

echo "Updated $FILE with ${#CHANGES[@]} change(s):"
printf '  %s\n' "${CHANGES[@]}"
echo "Done → $VERSION"
