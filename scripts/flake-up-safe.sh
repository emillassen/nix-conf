#!/usr/bin/env bash

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
# that actually break the build stay behind, everything else goes to its tip.
#
# An input that fails at its tip is not dropped all the way back to the baseline
# either. Its history is searched for the newest revision that does build, one
# candidate per day, so a nixpkgs that broke yesterday costs you one day instead
# of every day since your last commit. Pass --no-bisect to skip that search and
# settle for baseline-or-tip.
#
# It only ever chooses between revisions of an input — it never edits the config
# to work around a breakage (no overrides, no patching). If the newest mix it
# finds is not new enough, the fix belongs in the config, by hand.
#
# The lock that gets written is always built one final time before the run ends,
# so what you are left with is verified as a whole and not just as the sum of the
# steps that produced it. The working tree's flake.lock is restored on any failure
# or interrupt, so a run that dies halfway never leaves a half-searched lock behind.
#
# Options:
#   -n, --dry-run       list inputs with updates available; build nothing
#   -H, --host NAME     nixosConfiguration to build (default: the only one)
#   -t, --target ATTR   build this flake attr instead of the host's toplevel
#   -b, --baseline REF  known-good lock to fall back to: head (default) | worktree
#   -k, --check         also require `nix flake check` to pass
#   -B, --bisect        search held-back inputs for a working revision (default)
#       --no-bisect     do not search; an input is either at its tip or at baseline
#   -d, --max-days N    how far back the bisect will look (default 60)
#   -h, --help

set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$FLAKE_DIR/flake.lock"

DRY_RUN=0
HOST=""
TARGET=""
BASELINE="head"
RUN_CHECK=0
BISECT=1
MAX_DAYS=60

# Print the header comment block as help, so the two can never drift apart.
usage() {
  awk '
    NR == 1 { next }                                  # the shebang
    /^#/    { sub(/^# ?/, ""); print; found = 1; next }
    found   { exit }                                  # first line past the block
  ' "${BASH_SOURCE[0]}"
  exit "${1-0}"
}

die() {
  echo "error: $*" >&2
  exit 1
}

# Options that take a value must actually have been given one; without this a
# trailing `-H` silently shifts past the end of the argument list.
need_arg() {
  [ "$#" -ge 2 ] || die "$1 requires an argument"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  -n | --dry-run) DRY_RUN=1 ;;
  -H | --host)
    need_arg "$@"
    HOST="$2"
    shift
    ;;
  -t | --target)
    need_arg "$@"
    TARGET="$2"
    shift
    ;;
  -b | --baseline)
    need_arg "$@"
    BASELINE="$2"
    shift
    ;;
  -k | --check) RUN_CHECK=1 ;;
  -B | --bisect) BISECT=1 ;;
  --no-bisect) BISECT=0 ;;
  -d | --max-days)
    need_arg "$@"
    MAX_DAYS="$2"
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
*) die "--baseline must be 'head' or 'worktree', got '$BASELINE'" ;;
esac

case "$MAX_DAYS" in
'' | *[!0-9]*) die "--max-days must be a positive integer, got '$MAX_DAYS'" ;;
esac
[ "$MAX_DAYS" -gt 0 ] || die "--max-days must be greater than 0"

for tool in git jq nix; do
  command -v "$tool" >/dev/null || die "$tool not found in PATH"
done
if [ "$BISECT" -eq 1 ] && ! command -v gh >/dev/null 2>&1; then
  command -v curl >/dev/null || die "the bisect needs either gh or curl in PATH"
fi

[ -f "$LOCK" ] || die "$LOCK not found"

# Resolve the build target. With one nixosConfiguration (the usual case) the host
# needs no flag; with several, -H picks. A -t without a flake reference is taken
# as an attr of this flake, so `-t devilutionx` works from any directory.
if [ -n "$TARGET" ]; then
  case "$TARGET" in
  *'#'*) ;;
  *) TARGET="$FLAKE_DIR#$TARGET" ;;
  esac
else
  if [ -z "$HOST" ]; then
    mapfile -t HOSTS < <(
      nix eval --json --no-warn-dirty "$FLAKE_DIR#nixosConfigurations" \
        --apply builtins.attrNames 2>/dev/null | jq -r '.[]'
    )
    case "${#HOSTS[@]}" in
    1) HOST="${HOSTS[0]}" ;;
    0) die "no nixosConfigurations found in $FLAKE_DIR (pass -H NAME or -t ATTR)" ;;
    *) die "${#HOSTS[@]} nixosConfigurations found (${HOSTS[*]}), pass -H NAME" ;;
    esac
  fi
  TARGET="$FLAKE_DIR#nixosConfigurations.$HOST.config.system.build.toplevel"
fi

WORKDIR="$(mktemp -d -t flake-up-safe.XXXXXX)"
ORIG_LOCK="$WORKDIR/orig.lock"
BASELINE_LOCK="$WORKDIR/baseline.lock"
LOGDIR="$WORKDIR/logs"
LOCKCACHE="$WORKDIR/locks"
mkdir -p "$LOGDIR" "$LOCKCACHE"
cp "$LOCK" "$ORIG_LOCK"

KEPT=()
PINS=()
BISECTED=()
RED=()

RUN_START=$SECONDS
BUILDS=0
EVALS=0
SUCCESS=0
KEEP_LOGS=0

cleanup() {
  # Anything other than a completed search leaves flake.lock exactly as found.
  if [ "$SUCCESS" -eq 0 ] && [ -f "$ORIG_LOCK" ]; then
    cp "$ORIG_LOCK" "$LOCK"
    echo >&2
    echo "flake.lock restored to its original contents." >&2
    echo "logs kept in $WORKDIR" >&2
  elif [ "$KEEP_LOGS" -eq 1 ]; then
    echo
    echo "logs kept in $WORKDIR"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT
# Without these, a Ctrl-C lands inside whichever `nix build` is running and the
# script would carry on to the next trial with that one recorded as a failure.
trap 'echo >&2; echo "interrupted." >&2; exit 130' INT TERM HUP

# --- Reading the lock ---------------------------------------------------------
# Straight out of flake.lock with jq rather than `nix flake metadata`: the lock
# file already holds everything needed, and reading it costs no evaluation, no
# network and no copy of the working tree into the store.

# name<TAB>rev<TAB>lastModified for every top-level input.
lock_revs() {
  jq -r '
    . as $l
    | $l.nodes.root.inputs
    | to_entries[]
    | .key as $name
    | (if (.value | type) == "string" then .value else .value[-1] end) as $node
    | $l.nodes[$node].locked
    | "\($name)\t\(.rev // .narHash // "?")\t\(.lastModified // 0)"
  ' "$LOCK"
}

# owner/repo<TAB>ref for one input, taken from its `original` (the flake.nix
# declaration), not its `locked` — the branch is what history to walk.
input_origin() {
  jq -r --arg n "$1" '
    . as $l
    | $l.nodes.root.inputs[$n] as $v
    | (if ($v | type) == "string" then $v else $v[-1] end) as $node
    | $l.nodes[$node].original
    | if .type != "github" then "" else "\(.owner)/\(.repo)\t\(.ref // "HEAD")" end
  ' "$LOCK"
}

day_of() { date -u -d "@$1" +%F; }

# --- Composing candidate locks ------------------------------------------------
# Every composed lock is cached under its recipe. That keeps the run reproducible
# — a tip that moves mid-run cannot change what a later trial is testing — and it
# keeps the bisect from re-fetching the same set of inputs once per candidate.

lock_key() { printf '%s\n' "$@" | sort | sha256sum | cut -c1-32; }

# Reset to the baseline lock, then move only the named inputs to their tips.
# With no arguments this resets to the baseline and moves nothing: `nix flake
# update` with no input arguments means "all", which is update_all's job.
apply() {
  local key cached
  key="$(lock_key "$@")"
  cached="$LOCKCACHE/$key.lock"
  if [ -f "$cached" ]; then
    cp "$cached" "$LOCK"
    return 0
  fi
  cp "$BASELINE_LOCK" "$LOCK"
  if [ "$#" -gt 0 ]; then
    nix flake update --flake "$FLAKE_DIR" --no-warn-dirty "$@" \
      >"$LOGDIR/update.log" 2>&1 || {
      echo "error: nix flake update failed for: $*" >&2
      cat "$LOGDIR/update.log" >&2
      exit 1
    }
  fi
  cp "$LOCK" "$cached"
}

# Reset to the baseline, then move every input to its tip.
update_all() {
  cp "$BASELINE_LOCK" "$LOCK"
  nix flake update --flake "$FLAKE_DIR" --no-warn-dirty \
    >"$LOGDIR/update-all.log" 2>&1 || {
    echo "error: nix flake update failed" >&2
    cat "$LOGDIR/update-all.log" >&2
    exit 1
  }
}

# Pin one input to a specific revision. Only `locked` moves: `original` keeps the
# branch from flake.nix, so a later plain `nix flake update` still follows that
# branch forward rather than staying frozen at the pinned revision. The flake
# path is explicit — `nix flake lock` otherwise operates on the current working
# directory, which is not this flake when the script is run from elsewhere.
pin_input() {
  local name="$1" slug="$2" rev="$3"
  nix flake lock "$FLAKE_DIR" --override-input "$name" "github:$slug/$rev" \
    --no-warn-dirty >>"$LOGDIR/pin.log" 2>&1 || {
    echo "      error: could not pin $name to ${rev:0:10} (see $LOGDIR/pin.log)" >&2
    return 1
  }
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

# --- Trials -------------------------------------------------------------------
# A trial is split into evaluation and build so the two can be cached separately.
# Evaluation yields the target's .drv path, and equal .drv paths mean an
# identical build: an input whose update does not reach the target — a dev-shell
# or checks-only input, most commonly — resolves to a verdict already on record
# and costs nothing at all. Building the .drv directly then skips the second
# evaluation `nix build` on the flake attr would otherwise do.

declare -A DRV_VERDICT DRV_TRIAL LOCK_CHECKED

abort_if_interrupted() {
  local rc="$1" log="$2"
  if [ "$rc" -gt 128 ] || grep -q 'interrupted by the user' "$log" 2>/dev/null; then
    echo >&2
    echo "interrupted." >&2
    exit 130
  fi
}

# Pull the one line worth reading out of a nix failure. An evaluation trace
# opens with a bare `error:` and puts the actual cause at the very bottom, while
# a build failure states its case immediately, so the last error line carrying a
# message is the right pick for both.
report_error() {
  local log="$1" line
  line="$(grep -aE '(^|[[:space:]])error: .+' "$log" | tail -n1 || true)"
  [ -n "$line" ] || line="$(grep -am1 -E '^error' "$log" || true)"
  [ -n "$line" ] && printf '      %s\n' "$(printf '%s' "${line#"${line%%[![:space:]]*}"}" | cut -c1-200)"
  # For a failed builder its own last words beat anything nix says about it.
  grep -a '^ *> ' "$log" | tail -n3 | sed 's/^ */      /' | cut -c1-200 || true
  printf '      log: %s\n' "$log"
}

# Build (and optionally check) the current lock. Returns nonzero on any failure.
trial() {
  local tag="$1" log="$LOGDIR/$1.log" start=$SECONDS elapsed rc out drv

  : >"$log"
  EVALS=$((EVALS + 1))
  rc=0
  out="$(nix path-info --derivation --no-warn-dirty "$TARGET" 2>"$log")" || rc=$?
  drv="${out%%$'\n'*}"
  if [ "$rc" -ne 0 ] || [ -z "$drv" ]; then
    abort_if_interrupted "$rc" "$log"
    printf '    ✗ evaluation failed (%ds)\n' "$((SECONDS - start))"
    report_error "$log"
    return 1
  fi

  if [ -n "${DRV_VERDICT[$drv]-}" ]; then
    if [ "${DRV_VERDICT[$drv]}" = ok ]; then
      printf '    ✓ builds (identical to %s)\n' "${DRV_TRIAL[$drv]}"
      check_lock "$log" "$start"
      return
    fi
    printf '    ✗ failed (identical to %s)\n' "${DRV_TRIAL[$drv]}"
    return 1
  fi

  BUILDS=$((BUILDS + 1))
  rc=0
  nix build --no-link --no-warn-dirty "$drv^*" >>"$log" 2>&1 || rc=$?
  elapsed=$((SECONDS - start))
  DRV_TRIAL[$drv]="$tag"
  if [ "$rc" -ne 0 ]; then
    abort_if_interrupted "$rc" "$log"
    DRV_VERDICT[$drv]=bad
    printf '    ✗ failed (%ds)\n' "$elapsed"
    report_error "$log"
    return 1
  fi
  DRV_VERDICT[$drv]=ok
  printf '    ✓ builds (%ds)\n' "$elapsed"
  check_lock "$log" "$start"
}

# `nix flake check` covers outputs the target's .drv says nothing about, so it is
# keyed on the lock file itself rather than on the .drv.
check_lock() {
  local log="$1" start="$2" hash rc
  [ "$RUN_CHECK" -eq 1 ] || return 0
  hash="$(sha256sum <"$LOCK" | cut -c1-32)"
  if [ -n "${LOCK_CHECKED[$hash]-}" ]; then
    [ "${LOCK_CHECKED[$hash]}" = ok ] && return 0
    return 1
  fi
  rc=0
  nix flake check --no-warn-dirty "$FLAKE_DIR" >>"$log" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    abort_if_interrupted "$rc" "$log"
    LOCK_CHECKED[$hash]=bad
    printf '    ✗ flake check failed (%ds)\n' "$((SECONDS - start))"
    report_error "$log"
    return 1
  fi
  LOCK_CHECKED[$hash]=ok
  printf '    ✓ flake check passed (%ds)\n' "$((SECONDS - start))"
}

# --- The GitHub side of the bisect --------------------------------------------

# gh is authenticated and has the higher rate limit, so prefer it; fall back to
# plain curl (60 req/h unauthenticated, or set GITHUB_TOKEN).
gh_json() {
  if command -v gh >/dev/null 2>&1; then
    gh api "$1" 2>>"$LOGDIR/github.log"
  elif [ -n "${GITHUB_TOKEN-}" ]; then
    curl -sfL -H "Authorization: Bearer $GITHUB_TOKEN" "https://api.github.com/$1"
  else
    curl -sfL "https://api.github.com/$1"
  fi
}

# The tip of $ref as it stood at the end of $day. Days are the right granularity
# here — it is the unit the breakage is actually measured in ("nixpkgs broke
# yesterday"), and it keeps the candidate list to a handful instead of the
# thousands of individual commits between two lock positions.
#
# Resolved on demand and memoised: the search only ever visits a logarithmic
# number of days, so asking GitHub about all of them up front would spend sixty
# requests to use six.
# The answer lands in DAY_REV_RESULT rather than on stdout: a command
# substitution would run this in a subshell, and the memo would die with it.
declare -A DAY_REV
DAY_REV_RESULT=""
day_rev() {
  local slug="$1" ref="$2" day="$3" key="$1 $2 $3" out
  if [ -z "${DAY_REV[$key]-}" ]; then
    # A GitHub hiccup must not take the whole run down; an unresolved day is
    # simply one the search cannot use.
    out="$(gh_json "repos/$slug/commits?sha=$ref&until=${day}T23:59:59Z&per_page=1" |
      jq -r '.[0].sha // empty' 2>/dev/null || true)"
    DAY_REV[$key]="${out:--}"
  fi
  DAY_REV_RESULT="${DAY_REV[$key]}"
  [ "$DAY_REV_RESULT" != "-" ]
}

# Test candidate day index $4 for input $1. Consecutive days often resolve to the
# same commit (a quiet weekend on the branch), and the two ends of the range are
# known before the search starts, so verdicts are cached per revision too.
declare -A REV_VERDICT
try_day() {
  local name="$1" slug="$2" ref="$3" idx="$4" day rev rc
  day="${CAND_DAYS[$idx]}"
  if ! day_rev "$slug" "$ref" "$day"; then
    printf '    %s  (no commit found; treating as unusable)\n' "$day"
    return 1
  fi
  rev="$DAY_REV_RESULT"
  if [ -n "${REV_VERDICT[$rev]-}" ]; then
    printf '    %s  %s  (already known: %s)\n' "$day" "${rev:0:10}" "${REV_VERDICT[$rev]}"
    [ "${REV_VERDICT[$rev]}" = ok ] && return 0
    return 1
  fi
  printf '    %s  %s\n' "$day" "${rev:0:10}"
  rc=0
  apply_state "$name $slug $rev" || return 1
  trial "bisect-$name-${rev:0:8}" || rc=$?
  if [ "$rc" -eq 0 ]; then REV_VERDICT[$rev]=ok; else REV_VERDICT[$rev]=bad; fi
  return "$rc"
}

echo "flake:    $FLAKE_DIR"
echo "target:   $TARGET"
echo "baseline: $BASELINE"
echo

# --- Baseline -----------------------------------------------------------------
# The search is only meaningful relative to a lock that is known to build, since
# every candidate is baseline + some inputs moved forward.
if [ "$BASELINE" = "head" ]; then
  git -C "$FLAKE_DIR" show 'HEAD:./flake.lock' >"$BASELINE_LOCK" 2>/dev/null ||
    die "could not read flake.lock from HEAD (try --baseline worktree)"
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
    printf '  ↻ %-24s %s → %s\n' "$name" \
      "$(day_of "${BASE_TS[$name]}")" "$(day_of "${TIP_TS[$name]}")"
  else
    printf '  = %-24s unchanged (%s)\n' "$name" "$(day_of "${BASE_TS[$name]}")"
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
  for name in "${UPDATABLE[@]}"; do
    printf '  %-24s %s → %s\n' "$name" \
      "$(day_of "${BASE_TS[$name]}")" "$(day_of "${TIP_TS[$name]}")"
  done
  exit 0
fi

# The all-at-tips lock is exactly what `apply` would compute for the full set,
# and it has just been computed, so hand it to the cache instead of refetching.
cp "$LOCK" "$LOCKCACHE/$(lock_key "${UPDATABLE[@]}").lock"

echo "Verifying the baseline builds..."
cp "$BASELINE_LOCK" "$LOCK"
if ! trial baseline; then
  KEEP_LOGS=1
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
  printf 'Verified in %s (%d build(s), %d evaluation(s)).\n' \
    "$(printf '%dm%02ds' $(((SECONDS - RUN_START) / 60)) $(((SECONDS - RUN_START) % 60)))" \
    "$BUILDS" "$EVALS"
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
  # Not an exit: there may still be a working revision short of the tip for
  # these, which is exactly the case the bisect is for.
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
# doubles (1, 2, 4, 8…) so a boundary far from the tip does not cost one build
# per day either, and the bracket that straddles the boundary is then
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

    # One candidate per day, from the day before the tip back to the baseline's
    # own day. The tip is already known bad and the baseline already known good,
    # so both ends are seeded as verdicts rather than tested.
    CAND_DAYS=()
    ts=$((TIP_TS[$name] - 86400))
    while [ "$ts" -ge "${BASE_TS[$name]}" ] && [ "${#CAND_DAYS[@]}" -lt "$MAX_DAYS" ]; do
      CAND_DAYS+=("$(day_of "$ts")")
      ts=$((ts - 86400))
    done
    REV_VERDICT["${TIP_REV[$name]}"]=bad
    REV_VERDICT["${BASE_REV[$name]}"]=ok

    if [ "${#CAND_DAYS[@]}" -eq 0 ]; then
      printf '  %s: no days between baseline and tip to try\n' "$name"
      continue
    fi
    printf '  %s: %d candidate day(s), newest first\n' "$name" "${#CAND_DAYS[@]}"

    lo=-1 # newest index known to fail
    hi=-1 # oldest index known to build
    step=1
    idx=0
    while [ "$idx" -lt "${#CAND_DAYS[@]}" ]; do
      if try_day "$name" "$slug" "$ref" "$idx"; then
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
      if try_day "$name" "$slug" "$ref" "$mid"; then
        hi="$mid"
      else
        lo="$mid"
      fi
    done

    day="${CAND_DAYS[$hi]}"
    day_rev "$slug" "$ref" "$day"
    rev="$DAY_REV_RESULT"
    # The walk can land on the baseline itself when nothing in between builds;
    # that is not an improvement and must not become a pin.
    if [ "$rev" = "${BASE_REV[$name]}" ]; then
      printf '    → nothing newer than the baseline builds; staying at baseline\n'
      continue
    fi
    PINS+=("$name $slug $rev")
    BISECTED+=("$name $day $rev")
    printf '    → newest working: %s (%s)\n' "$day" "${rev:0:10}"
  done
  echo
fi

# --- Final verification -------------------------------------------------------
# Recompose the winning combination so the lock on disk is exactly what gets
# reported, then build it as a whole. The steps above each verified a state, but
# the composition of all of them is its own state, and it is the one being
# written. Thanks to the .drv cache this is usually free.
apply_state || die "could not recompose the winning combination"

if [ "${#KEPT[@]}" -gt 0 ] || [ "${#BISECTED[@]}" -gt 0 ]; then
  echo "Verifying the result as a whole..."
  if ! trial final; then
    KEEP_LOGS=1
    echo
    echo "The combination that each step accepted does not build together." >&2
    echo "Falling back to the $BASELINE baseline." >&2
    cp "$BASELINE_LOCK" "$LOCK"
    KEPT=()
    BISECTED=()
    PINS=()
  fi
  echo
fi

STILL_BACK=()
for name in "${RED[@]}"; do
  pinned=0
  for b in "${BISECTED[@]}"; do
    [ "${b%% *}" = "$name" ] && pinned=1
  done
  [ "$pinned" -eq 0 ] && STILL_BACK+=("$name")
done

SUCCESS=1
[ "${#STILL_BACK[@]}" -gt 0 ] && KEEP_LOGS=1

if [ "${#KEPT[@]}" -eq 0 ] && [ "${#BISECTED[@]}" -eq 0 ]; then
  if cmp -s "$ORIG_LOCK" "$LOCK"; then
    echo "Nothing improved on the baseline; flake.lock unchanged."
  else
    echo "Nothing improved on the baseline; flake.lock reset to the $BASELINE lock."
  fi
else
  echo "Wrote flake.lock (verified):"
  for name in "${KEPT[@]}"; do
    printf '  at tip     %-22s %s → %s\n' "$name" \
      "$(day_of "${BASE_TS[$name]}")" "$(day_of "${TIP_TS[$name]}")"
  done
  for b in "${BISECTED[@]}"; do
    read -r bname bday brev <<<"$b"
    printf '  bisected   %-22s %s → %s (%s), tip was %s\n' \
      "$bname" "$(day_of "${BASE_TS[$bname]}")" "$bday" "${brev:0:10}" \
      "$(day_of "${TIP_TS[$bname]}")"
  done
fi

for name in "${STILL_BACK[@]}"; do
  printf '  held back  %-22s stays at %s\n' "$name" "$(day_of "${BASE_TS[$name]}")"
done

printf '\nDone in %s (%d build(s), %d evaluation(s)).\n' \
  "$(printf '%dm%02ds' $(((SECONDS - RUN_START) / 60)) $(((SECONDS - RUN_START) % 60)))" \
  "$BUILDS" "$EVALS"

if [ "${#STILL_BACK[@]}" -gt 0 ]; then
  echo
  if [ "$BISECT" -eq 1 ]; then
    echo "No revision newer than the baseline builds for the held-back input(s)."
    echo "Re-run in a few days, or fix the breakage in the config by hand."
  else
    echo "These stay at the baseline. Re-run without --no-bisect to search their"
    echo "history for the newest revision that does build."
  fi
fi
