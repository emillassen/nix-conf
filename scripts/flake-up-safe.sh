#!/usr/bin/env nix-shell
#! nix-shell -i bash -p jq curl

# Find the newest combination of flake inputs that still builds this system, and
# write it to flake.lock.
#
#   ./flake-up-safe.sh        search, then write the best flake.lock found
#   ./flake-up-safe.sh -n     report which inputs have updates, build nothing
#
# `flake-up` (nix flake update) moves every input to its tip at once, so a single
# broken input takes the whole lock down with it. Reverting to the committed lock
# then throws away the other ten inputs' updates too, which is how a rollback ends
# up older than it needs to be. This keeps per-input granularity: only the inputs
# that actually break the build stay at the baseline, everything else goes to its
# tip.
#
# It only ever chooses between "input at baseline" and "input at tip" — it never
# edits the config to work around a breakage (no pinning, no overrides, no
# patching). If the newest mix it finds is not new enough, the fix belongs in the
# config, by hand.
#
# The working tree's flake.lock is restored on any failure or interrupt, so a run
# that dies halfway never leaves a half-searched lock behind.
#
# With --bisect, an input that fails at its tip is not dropped all the way back
# to the baseline. Its history is searched for the newest revision that does
# build, one candidate per day, so a nixpkgs that broke yesterday costs you one
# day instead of every day since your last commit.
#
# Options:
#   -n, --dry-run       list inputs with updates available; build nothing
#   -H, --host NAME     nixosConfiguration to build (default: the only one)
#   -t, --target ATTR   build this flake attr instead of the host's toplevel
#   -b, --baseline REF  known-good lock to fall back to: head (default) | worktree
#   -k, --check         also require `nix flake check` to pass
#   -B, --bisect        search held-back inputs for their newest working revision
#   -d, --max-days N    how far back --bisect will look (default 60)
#   -h, --help

set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$FLAKE_DIR/flake.lock"

DRY_RUN=0
HOST=""
TARGET=""
BASELINE="head"
RUN_CHECK=0
BISECT=0
MAX_DAYS=60

# Print the header comment block as help, so the two can never drift apart.
usage() {
  awk '
    NR <= 2 { next }                                  # the nix-shell shebang
    /^#/    { sub(/^# ?/, ""); print; found = 1; next }
    found   { exit }                                  # first line past the block
  ' "$0"
  exit "${1-0}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  -n | --dry-run) DRY_RUN=1 ;;
  -H | --host)
    HOST="${2-}"
    shift
    ;;
  -t | --target)
    TARGET="${2-}"
    shift
    ;;
  -b | --baseline)
    BASELINE="${2-}"
    shift
    ;;
  -k | --check) RUN_CHECK=1 ;;
  -B | --bisect) BISECT=1 ;;
  -d | --max-days)
    MAX_DAYS="${2-}"
    shift
    ;;
  -h | --help) usage 0 ;;
  *)
    echo "error: unknown argument: $1" >&2
    usage 2 >&2
    ;;
  esac
  shift
done

case "$BASELINE" in
head | worktree) ;;
*)
  echo "error: --baseline must be 'head' or 'worktree', got '$BASELINE'" >&2
  exit 2
  ;;
esac

case "$MAX_DAYS" in
'' | *[!0-9]*)
  echo "error: --max-days must be a positive integer, got '$MAX_DAYS'" >&2
  exit 2
  ;;
esac

for tool in git jq nix; do
  command -v "$tool" >/dev/null ||
    { echo "error: $tool not found in PATH" >&2; exit 1; }
done

[ -f "$LOCK" ] || { echo "error: $LOCK not found" >&2; exit 1; }

# Resolve the build target. With one nixosConfiguration (the usual case) the host
# needs no flag; with several, -H picks.
if [ -z "$TARGET" ]; then
  if [ -z "$HOST" ]; then
    mapfile -t HOSTS < <(
      nix eval --json --no-warn-dirty "$FLAKE_DIR#nixosConfigurations" \
        --apply builtins.attrNames 2>/dev/null | jq -r '.[]'
    )
    if [ "${#HOSTS[@]}" -eq 1 ]; then
      HOST="${HOSTS[0]}"
    else
      echo "error: ${#HOSTS[@]} nixosConfigurations found, pass -H NAME" >&2
      exit 1
    fi
  fi
  TARGET="$FLAKE_DIR#nixosConfigurations.$HOST.config.system.build.toplevel"
fi

WORKDIR="$(mktemp -d -t flake-up-safe.XXXXXX)"
ORIG_LOCK="$WORKDIR/orig.lock"
BASELINE_LOCK="$WORKDIR/baseline.lock"
LOGDIR="$WORKDIR/logs"
mkdir -p "$LOGDIR"
cp "$LOCK" "$ORIG_LOCK"

KEPT=()
PINS=()
BISECTED=()
RED=()

SUCCESS=0
cleanup() {
  # Anything other than a completed search leaves flake.lock exactly as found.
  if [ "$SUCCESS" -eq 0 ] && [ -f "$ORIG_LOCK" ]; then
    cp "$ORIG_LOCK" "$LOCK"
    echo >&2
    echo "flake.lock restored to its original contents." >&2
    echo "logs kept in $WORKDIR" >&2
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

# name<TAB>rev<TAB>lastModified for every top-level input, read back out of the lock.
lock_revs() {
  nix flake metadata --json --no-warn-dirty "$FLAKE_DIR" | jq -r '
    . as $m
    | $m.locks.nodes.root.inputs
    | to_entries[]
    | .key as $name
    | (if (.value | type) == "string" then .value else .value[-1] end) as $node
    | $m.locks.nodes[$node].locked
    | "\($name)\t\(.rev // .narHash // "?")\t\(.lastModified // 0)"
  '
}

# owner/repo<TAB>ref for one input, taken from its `original` (the flake.nix
# declaration), not its `locked` — the branch is what history to walk.
input_origin() {
  nix flake metadata --json --no-warn-dirty "$FLAKE_DIR" | jq -r --arg n "$1" '
    . as $m
    | $m.locks.nodes.root.inputs[$n] as $v
    | (if ($v | type) == "string" then $v else $v[-1] end) as $node
    | $m.locks.nodes[$node].original
    | if .type != "github" then "" else
        "\(.owner)/\(.repo)\t\(.ref // "HEAD")"
      end
  '
}

# gh is authenticated and has the higher rate limit, so prefer it; fall back to
# plain curl (60 req/h unauthenticated, or set GITHUB_TOKEN).
gh_json() {
  if command -v gh >/dev/null 2>&1; then
    gh api "$1" 2>/dev/null
  elif [ -n "${GITHUB_TOKEN-}" ]; then
    curl -sfL -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/$1"
  else
    curl -sfL "https://api.github.com/$1"
  fi
}

# One candidate revision per calendar day, newest first: the tip of $ref as it
# stood at the end of that day. Days are the right granularity here — it is the
# unit the breakage is actually measured in ("nixpkgs broke yesterday"), and it
# keeps the candidate list to a handful instead of the thousands of individual
# commits between two lock positions.
candidate_revs() {
  local slug="$1" ref="$2" newest_ts="$3" oldest_ts="$4"
  local day ts="$newest_ts" rev seen="" n=0
  while [ "$ts" -ge "$oldest_ts" ] && [ "$n" -lt "$MAX_DAYS" ]; do
    day="$(date -u -d "@$ts" +%F)"
    rev="$(gh_json "repos/$slug/commits?sha=$ref&until=${day}T23:59:59Z&per_page=1" |
      jq -r '.[0].sha // empty')"
    ts=$((ts - 86400))
    n=$((n + 1))
    [ -n "$rev" ] || continue
    # A day with no commits repeats the previous day's tip.
    case " $seen " in *" $rev "*) continue ;; esac
    seen="$seen $rev"
    printf '%s\t%s\n' "$day" "$rev"
  done
}

# Reset to the baseline lock, then move only the named inputs to their tips.
# With no arguments this resets to the baseline and moves nothing — updating
# every input is update_all's job, since `nix flake update` with no input
# arguments means "all" and would otherwise fire on an empty candidate list.
apply() {
  cp "$BASELINE_LOCK" "$LOCK"
  if [ "$#" -gt 0 ]; then
    nix flake update --flake "$FLAKE_DIR" --no-warn-dirty "$@" \
      >"$LOGDIR/update.log" 2>&1 ||
      { echo "error: nix flake update failed for: $*" >&2
        cat "$LOGDIR/update.log" >&2; exit 1; }
  fi
}

# Reset to the baseline, then move every input to its tip.
update_all() {
  cp "$BASELINE_LOCK" "$LOCK"
  nix flake update --flake "$FLAKE_DIR" --no-warn-dirty \
    >"$LOGDIR/update-all.log" 2>&1 ||
    { echo "error: nix flake update failed" >&2
      cat "$LOGDIR/update-all.log" >&2; exit 1; }
}

# Pin one input to a specific revision. Only `locked` moves: `original` keeps the
# branch from flake.nix, so a later plain `nix flake update` still follows that
# branch forward rather than staying frozen at the pinned revision.
pin_input() {
  local name="$1" slug="$2" rev="$3"
  nix flake lock --override-input "$name" "github:$slug/$rev" --no-warn-dirty \
    >>"$LOGDIR/pin.log" 2>&1 ||
    { echo "      error: could not pin $name to ${rev:0:10}" >&2; return 1; }
}

# Reset to the baseline, move the kept inputs to their tips, re-apply every
# revision pin decided so far, then any extra "name slug rev" passed as an
# argument. Rebuilt from the baseline every time so trials never accumulate.
apply_state() {
  apply "${KEPT[@]}"
  local p pname pslug prev
  for p in "${PINS[@]}" "$@"; do
    [ -n "$p" ] || continue
    read -r pname pslug prev <<<"$p"
    pin_input "$pname" "$pslug" "$prev" || return 1
  done
}

# Test candidate index $3 of CANDS for input $1 (repo slug $2).
try_candidate() {
  local name="$1" slug="$2" idx="$3" day rev
  day="${CANDS[$idx]%%$'\t'*}"
  rev="${CANDS[$idx]#*$'\t'}"
  printf '    %s  %s\n' "$day" "${rev:0:10}"
  apply_state "$name $slug $rev" || return 1
  trial "bisect-$name-${rev:0:8}"
}

# Build (and optionally check) the current lock. Returns nonzero on any failure.
trial() {
  local log="$LOGDIR/$1.log" start=$SECONDS elapsed
  local ok=1
  nix build "$TARGET" --no-link --no-warn-dirty >"$log" 2>&1 || ok=0
  if [ "$ok" -eq 1 ] && [ "$RUN_CHECK" -eq 1 ]; then
    nix flake check --no-warn-dirty "$FLAKE_DIR" >>"$log" 2>&1 || ok=0
  fi
  elapsed=$((SECONDS - start))
  if [ "$ok" -eq 1 ]; then
    printf '    ✓ builds (%ds)\n' "$elapsed"
    return 0
  fi
  printf '    ✗ failed (%ds)\n' "$elapsed"
  # The first error line is nearly always the useful one.
  grep -m1 -E '^error:|error: Cannot build' "$log" | sed 's/^/      /' || true
  printf '      log: %s\n' "$log"
  return 1
}

echo "flake:    $FLAKE_DIR"
echo "target:   $TARGET"
echo "baseline: $BASELINE"
echo

# --- Baseline -----------------------------------------------------------------
# The search is only meaningful relative to a lock that is known to build, since
# every candidate is baseline + some inputs moved forward.
if [ "$BASELINE" = "head" ]; then
  git -C "$FLAKE_DIR" show HEAD:flake.lock >"$BASELINE_LOCK" 2>/dev/null ||
    { echo "error: could not read flake.lock from HEAD" >&2; exit 1; }
else
  cp "$ORIG_LOCK" "$BASELINE_LOCK"
fi

cp "$BASELINE_LOCK" "$LOCK"
declare -A BASE_REV BASE_TS
while IFS=$'\t' read -r name rev ts; do
  BASE_REV[$name]="$rev"
  BASE_TS[$name]="$ts"
done < <(lock_revs)

# --- What is even available ---------------------------------------------------
echo "Checking for input updates..."
update_all
declare -A TIP_REV TIP_TS
while IFS=$'\t' read -r name rev ts; do
  TIP_REV[$name]="$rev"
  TIP_TS[$name]="$ts"
done < <(lock_revs)

UPDATABLE=()
for name in $(printf '%s\n' "${!BASE_REV[@]}" | sort); do
  if [ "${BASE_REV[$name]}" != "${TIP_REV[$name]-}" ]; then
    UPDATABLE+=("$name")
    printf '  ↻ %-24s %s → %s\n' "$name" "${BASE_REV[$name]:0:10}" "${TIP_REV[$name]:0:10}"
  else
    printf '  = %-24s unchanged\n' "$name"
  fi
done
echo

if [ "${#UPDATABLE[@]}" -eq 0 ]; then
  # Nothing to search means nothing was verified either, so the working tree is
  # left exactly as found rather than being overwritten with an untested lock.
  cp "$ORIG_LOCK" "$LOCK"
  SUCCESS=1
  echo "Every input is already at its tip — nothing to search, flake.lock untouched."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  cp "$ORIG_LOCK" "$LOCK"
  SUCCESS=1
  echo "${#UPDATABLE[@]} input(s) have updates (dry run, nothing built, flake.lock untouched):"
  printf '  %s\n' "${UPDATABLE[@]}"
  exit 0
fi

echo "Verifying the baseline builds..."
cp "$BASELINE_LOCK" "$LOCK"
if ! trial baseline; then
  echo >&2
  echo "error: the $BASELINE baseline does not build on its own." >&2
  echo "Nothing can be concluded about the inputs until that is fixed." >&2
  exit 1
fi
echo

# --- Fast path: everything at once --------------------------------------------
echo "Trying all ${#UPDATABLE[@]} update(s) together..."
apply "${UPDATABLE[@]}"
if trial all; then
  SUCCESS=1
  echo
  echo "All inputs updated cleanly — flake.lock written."
  exit 0
fi
echo

# --- Per-input: which ones are safe on their own ------------------------------
echo "Testing each input on its own against the baseline..."
GREEN=()
RED=()
i=0
for name in "${UPDATABLE[@]}"; do
  i=$((i + 1))
  printf '  [%d/%d] %s\n' "$i" "${#UPDATABLE[@]}" "$name"
  apply "$name"
  if trial "only-$name"; then
    GREEN+=("$name")
  else
    RED+=("$name")
  fi
done
echo

if [ "${#GREEN[@]}" -eq 0 ]; then
  # Not an exit: with --bisect there may still be a working revision short of
  # the tip for these, which is exactly the case worth searching.
  KEPT=()
  echo "No input can move forward to its tip on its own."
  echo
else
  # --- Combine the safe ones --------------------------------------------------
  # Green-alone does not imply green-together, so the combination is tested too,
  # and narrowed one input at a time if it fails.
  echo "Combining the ${#GREEN[@]} input(s) that passed alone..."
  apply "${GREEN[@]}"
  if trial combined; then
    KEPT=("${GREEN[@]}")
  else
    echo
    echo "  Combination failed — adding them one at a time instead."
    KEPT=()
    for name in "${GREEN[@]}"; do
      printf '  + %s\n' "$name"
      apply "${KEPT[@]}" "$name"
      if trial "with-$name"; then
        KEPT+=("$name")
      else
        RED+=("$name")
        printf '      (dropped: breaks in combination)\n'
      fi
    done
  fi
  echo
fi

# --- Bisect the held-back inputs ----------------------------------------------
# Everything above chose only between "input at baseline" and "input at tip", so
# a red input drops all the way back to the last committed lock — often far older
# than the newest revision that would actually have worked.
#
# Candidates run newest-first, and the search starts at the newest and walks
# back, so a breakage introduced yesterday costs a single build. The stride
# doubles (0, 1, 3, 7, 15…) so a boundary far from the tip does not cost one
# build per day either, and the bracket that straddles the boundary is then
# binary-searched: best case 1 build, worst case ~2·log2(days).
#
# This assumes the boundary is monotone — that once a revision builds, older ones
# do too. Breakages get introduced and later fixed, so that holds over the short
# windows involved here, but a fix-then-rebreak inside the window can make it
# settle on a working revision that is not strictly the newest one.
if [ "$BISECT" -eq 1 ] && [ "${#RED[@]}" -gt 0 ]; then
  echo "Bisecting ${#RED[@]} held-back input(s) for their newest working revision..."
  for name in "${RED[@]}"; do
    origin="$(input_origin "$name")"
    slug="${origin%%$'\t'*}"
    ref="${origin#*$'\t'}"
    if [ -z "$slug" ]; then
      printf '  %s: not a github input, cannot bisect\n' "$name"
      continue
    fi

    mapfile -t RAW < <(candidate_revs "$slug" "$ref" "${TIP_TS[$name]}" "${BASE_TS[$name]}")
    CANDS=()
    for c in "${RAW[@]}"; do
      crev="${c#*$'\t'}"
      # The tip is already known bad; the baseline is already known good and is
      # the fallback, so the search space is strictly between them.
      [ "$crev" = "${TIP_REV[$name]}" ] && continue
      [ "$crev" = "${BASE_REV[$name]}" ] && break
      CANDS+=("$c")
    done

    if [ "${#CANDS[@]}" -eq 0 ]; then
      printf '  %s: no revisions between baseline and tip to try\n' "$name"
      continue
    fi
    printf '  %s: %d candidate day(s), newest first\n' "$name" "${#CANDS[@]}"

    lo=-1 # newest index known to fail
    hi=-1 # oldest index known to build
    step=1
    idx=0
    while [ "$idx" -lt "${#CANDS[@]}" ]; do
      if try_candidate "$name" "$slug" "$idx"; then
        hi="$idx"
        break
      fi
      lo="$idx"
      idx=$((idx + step))
      step=$((step * 2))
    done

    if [ "$hi" -lt 0 ]; then
      printf '    → nothing newer than the baseline builds; staying at baseline\n'
      continue
    fi
    # Narrow (lo, hi] down to the newest revision that still builds.
    while [ $((hi - lo)) -gt 1 ]; do
      mid=$(((lo + hi) / 2))
      if try_candidate "$name" "$slug" "$mid"; then
        hi="$mid"
      else
        lo="$mid"
      fi
    done

    day="${CANDS[$hi]%%$'\t'*}"
    rev="${CANDS[$hi]#*$'\t'}"
    PINS+=("$name $slug $rev")
    BISECTED+=("$name $day $rev")
    printf '    → newest working: %s (%s)\n' "$day" "${rev:0:10}"
  done
  echo
fi

# Rebuild the winning combination one last time so the lock on disk is exactly
# what was reported (the last trial may have been a rejected candidate).
apply_state

STILL_BACK=()
for name in "${RED[@]}"; do
  pinned=0
  for b in "${BISECTED[@]}"; do
    [ "${b%% *}" = "$name" ] && pinned=1
  done
  [ "$pinned" -eq 0 ] && STILL_BACK+=("$name")
done

SUCCESS=1
if [ "${#KEPT[@]}" -eq 0 ] && [ "${#BISECTED[@]}" -eq 0 ]; then
  echo "Nothing improved on the baseline; keeping the baseline lock."
else
  echo "Wrote flake.lock:"
  [ "${#KEPT[@]}" -gt 0 ] &&
    printf '  at tip:      %s\n' "${KEPT[*]}"
fi

if [ "${#BISECTED[@]}" -gt 0 ]; then
  echo "  bisected:"
  for b in "${BISECTED[@]}"; do
    read -r bname bday brev <<<"$b"
    printf '    %-22s %s (%s), baseline was %s\n' \
      "$bname" "$bday" "${brev:0:10}" "$(date -u -d "@${BASE_TS[$bname]}" +%F)"
  done
fi

if [ "${#STILL_BACK[@]}" -gt 0 ]; then
  printf '  held back:   %s\n' "${STILL_BACK[*]}"
  echo
  if [ "$BISECT" -eq 1 ]; then
    echo "No revision newer than the baseline builds for these. Re-run in a few"
    echo "days, or fix the breakage in the config by hand."
  else
    echo "These stay at the baseline. Re-run with --bisect to search their history"
    echo "for the newest revision that does build."
  fi
fi
