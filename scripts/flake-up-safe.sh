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
# either. Its history is searched for the newest revision that does build, so a
# nixpkgs that broke yesterday costs you one day instead of every day since your
# last commit. For a nixpkgs input that tracks a channel the candidates are the
# channel's own releases, which is what keeps cache.nixos.org useful; for anything
# else they are one commit per day. Pass --no-bisect to skip that search and
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
#   -f, --flake DIR     the flake to work on (default: this script's own repo,
#                       else $NH_FLAKE, else the first flake.nix at or above $PWD)
#   -H, --host NAME     nixosConfiguration to build (default: the only one)
#   -t, --target ATTR   build this flake attr instead of the host's toplevel
#                       (names the build outright, so not alongside -H)
#   -i, --input NAME    only consider this input (repeatable)
#   -b, --baseline REF  known-good lock to fall back to: head (default) | worktree
#   -k, --check         also require `nix flake check` to pass
#   -B, --bisect        search held-back inputs for a working revision (default)
#       --no-bisect     do not search; an input is either at its tip or at baseline
#   -d, --max-days N    how many candidates back the bisect will look (default
#                       60). A candidate is a day for a commit search and a
#                       release for a channel, and a rolling channel publishes
#                       several a day, so this is a count and not a span
#   -l, --linear N      how many candidates the bisect checks one at a time
#                       before it starts skipping (default 7; 0 skips from the
#                       start, a large N never skips)
#   -v, --verbose       stream nix's own output instead of a progress line
#   -h, --help

set -euo pipefail

DRY_RUN=0
FLAKE_DIR=""
HOST=""
TARGET=""
BASELINE="head"
RUN_CHECK=0
BISECT=1
MAX_DAYS=60
LINEAR=7
VERBOSE=0
ONLY=()

# Print the header comment block as help, so the two can never drift apart.
# Anything before the block (a shebang, or the preamble a Nix wrapper injects)
# is skipped rather than assumed to be exactly one line.
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
  -f | --flake)
    need_arg "$@"
    FLAKE_DIR="$2"
    shift
    ;;
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
  -i | --input)
    need_arg "$@"
    ONLY+=("$2")
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
  -l | --linear)
    need_arg "$@"
    LINEAR="$2"
    shift
    ;;
  -v | --verbose) VERBOSE=1 ;;
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

case "$LINEAR" in
'' | *[!0-9]*) die "--linear must be a non-negative integer, got '$LINEAR'" ;;
esac

# --- Which flake ---------------------------------------------------------------
# Run from a checkout, the script belongs to the flake it sits in. Installed into
# the store by a Nix wrapper it does not, so fall back to what the rest of the
# system already agrees is "the" flake, and then to wherever the user is standing.
find_flake_root() {
  local dir="$1"
  dir="$(cd "$dir" 2>/dev/null && pwd)" || return 1
  while [ -n "$dir" ]; do
    [ -f "$dir/flake.nix" ] && {
      printf '%s\n' "$dir"
      return 0
    }
    [ "$dir" = "/" ] && return 1
    dir="$(dirname "$dir")"
  done
  return 1
}

if [ -n "$FLAKE_DIR" ]; then
  [ -d "$FLAKE_DIR" ] || die "no such directory: $FLAKE_DIR"
  FLAKE_DIR="$(cd "$FLAKE_DIR" && pwd)"
else
  FLAKE_DIR="$(find_flake_root "$(dirname "${BASH_SOURCE[0]}")/.." || true)"
  [ -n "$FLAKE_DIR" ] || FLAKE_DIR="$(find_flake_root "${NH_FLAKE-/nonexistent}" || true)"
  [ -n "$FLAKE_DIR" ] || FLAKE_DIR="$(find_flake_root "$PWD" || true)"
  [ -n "$FLAKE_DIR" ] || die "no flake.nix found (pass --flake DIR)"
fi

LOCK="$FLAKE_DIR/flake.lock"
[ -f "$LOCK" ] || die "$LOCK not found"

for tool in git jq nix; do
  command -v "$tool" >/dev/null || die "$tool not found in PATH"
done
command -v curl >/dev/null || die "curl not found in PATH"

# Resolve the build target. With one nixosConfiguration (the usual case) the host
# needs no flag; with several, -H picks. A -t without a flake reference is taken
# as an attr of this flake, so `-t devilutionx` works from any directory.
if [ -n "$TARGET" ]; then
  # -t names the thing to build outright, so a -H alongside it has nothing left
  # to decide. Ignoring one of two contradictory flags is the kind of thing you
  # find out about after a two-hour run built something else.
  [ -z "$HOST" ] || die "--target and --host cannot be combined (-t already names what to build)"
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
NORESOLVE=()

RUN_START=$SECONDS
BUILDS=0
EVALS=0
SUCCESS=0
KEEP_LOGS=0
TRIAL_N=0
TRIAL_OUT=""
BASELINE_OUT=""
FINAL_OUT=""

# A progress line is only useful on a terminal; in a pipe or a log it is noise.
if [ -t 1 ] && [ "$VERBOSE" -eq 0 ]; then TTY=1; else TTY=0; fi

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

fmt_dur() { printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); }

# --- Reading the lock ---------------------------------------------------------
# Straight out of flake.lock with jq rather than `nix flake metadata`: the lock
# file already holds everything needed, and reading it costs no evaluation, no
# network and no copy of the working tree into the store.

# An entry in root.inputs is usually the node's name outright. A top-level
# `follows` makes it a path to walk instead: ["a","b"] means "root's input a,
# then that node's input b". The last element of such a path is an *input* name,
# which is only by coincidence also the name of the node it leads to — and this
# repo's own lock is exactly where the coincidence fails, since llm-agents
# deliberately carries its own nixpkgs node. One `inputs.x.follows =
# "llm-agents/nixpkgs"` line would then have every function below reporting,
# comparing and pinning the wrong node's revision. So walk the path rather than
# taking its last element, and let a path that leads nowhere fall through to the
# defaults instead of aborting the run.
# shellcheck disable=SC2016 # $l and $seg are jq variables, not shell ones
JQ_NODE='
  def node($l): if type == "string" then . else
    reduce .[] as $seg ("root";
      ($l.nodes[.].inputs // {})[$seg]
      | if . == null then "" elif type == "string" then . else node($l) end)
  end;
'

# name<TAB>rev<TAB>lastModified for every top-level input.
lock_revs() {
  jq -r "$JQ_NODE"'
    . as $l
    | $l.nodes.root.inputs
    | to_entries[]
    | .key as $name
    | (.value | node($l)) as $node
    | $l.nodes[$node].locked
    | "\($name)\t\(.rev // .narHash // "?")\t\(.lastModified // 0)"
  ' "${1:-$LOCK}"
}

# The locked rev of one input, used to confirm a pin actually landed.
locked_rev() {
  jq -r --arg n "$1" "$JQ_NODE"'
    . as $l
    | ($l.nodes.root.inputs[$n] | node($l)) as $node
    | $l.nodes[$node].locked.rev // ""
  ' "$LOCK"
}

# The locked timestamp of one input, which is how "is this actually newer than
# the baseline" gets answered — revisions on their own carry no order.
locked_ts() {
  jq -r --arg n "$1" "$JQ_NODE"'
    . as $l
    | ($l.nodes.root.inputs[$n] | node($l)) as $node
    | $l.nodes[$node].locked.lastModified // 0
  ' "$LOCK"
}

# owner/repo<TAB>ref for one input, taken from its `original` (the flake.nix
# declaration), not its `locked` — the branch is what history to walk.
input_origin() {
  jq -r --arg n "$1" "$JQ_NODE"'
    . as $l
    | ($l.nodes.root.inputs[$n] | node($l)) as $node
    | $l.nodes[$node].original
    | if .type != "github" then "" else "\(.owner)/\(.repo)\t\(.ref // "HEAD")" end
  ' "$LOCK"
}

day_of() { date -u -d "@$1" +%F; }

# --- Composing candidate locks ------------------------------------------------
# A lock is described by a recipe of tokens: `tip:NAME` moves an input to its tip,
# `pin:NAME:OWNER/REPO:REV` pins one to a revision. Every composed lock is cached
# under its recipe. That keeps the run reproducible — a tip that moves mid-run
# cannot change what a later trial is testing — and it keeps the bisect from
# re-fetching the same set of inputs once per candidate.

lock_key() { printf '%s\n' "$@" | sort | sha256sum | cut -c1-32; }

# Pin one input to a specific revision. Only `locked` moves: `original` keeps the
# branch from flake.nix, so a later plain `nix flake update` still follows that
# branch forward rather than staying frozen at the pinned revision. The flake
# path is explicit — `nix flake lock` otherwise operates on the current working
# directory, which is not this flake when the script is run from elsewhere.
pin_input() {
  local name="$1" slug="$2" rev="$3" got
  nix flake lock "$FLAKE_DIR" --override-input "$name" "github:$slug/$rev" \
    --no-warn-dirty >>"$LOGDIR/pin.log" 2>&1 || {
    echo "      error: could not pin $name to ${rev:0:10} (see $LOGDIR/pin.log)" >&2
    return 1
  }
  # `--override-input` implying `--no-write-lock-file` has been proposed upstream
  # more than once. If a future Nix adopts it, every bisect verdict below would
  # silently be a verdict on the unpinned lock instead, so check rather than trust.
  got="$(locked_rev "$name")"
  [ "$got" = "$rev" ] || die "nix did not write the pin for $name (lock says '${got:0:10}', wanted ${rev:0:10})"
}

# One `nix flake update`, with the same single retry a build gets: resolving an
# input is a network operation, a blip during one says nothing about the inputs,
# and a run that has already spent an hour building should not be thrown away
# for it. Returns non-zero once the retry has been spent too.
run_flake_update() {
  local log="$1" attempt rc
  shift
  for attempt in 1 2; do
    rc=0
    nix flake update --flake "$FLAKE_DIR" --no-warn-dirty "$@" >"$log" 2>&1 || rc=$?
    [ "$rc" -eq 0 ] && return 0
    if [ "$attempt" -eq 1 ] && is_transient "$log"; then
      echo "    … network trouble resolving inputs, retrying once" >&2
      continue
    fi
    return 1
  done
}

# Reset to the baseline lock and apply a recipe. Tips first, pins second: a
# `nix flake update` after a pin would undo it. Rebuilt from the baseline every
# time, so trials never accumulate.
compose() {
  local key cached tips=() pins=() t p pname pslug prev origin slug
  key="$(lock_key "$@")"
  cached="$LOCKCACHE/$key.lock"
  if [ -f "$cached" ]; then
    cp "$cached" "$LOCK"
    return 0
  fi
  for t in "$@"; do
    case "$t" in
    tip:*) tips+=("${t#tip:}") ;;
    pin:*) pins+=("${t#pin:}") ;;
    esac
  done
  cp "$BASELINE_LOCK" "$LOCK"
  # `nix flake update` with no input arguments means "all", which is never what a
  # recipe asks for — the all-tips lock is composed from the full name list.
  if [ "${#tips[@]}" -gt 0 ]; then
    run_flake_update "$LOGDIR/update.log" "${tips[@]}" || {
      echo "error: nix flake update failed for: ${tips[*]}" >&2
      cat "$LOGDIR/update.log" >&2
      exit 1
    }
    # Unlike update_all this deliberately does not --refresh, so it answers out
    # of nix's tarball-ttl cache — and once that hour has passed, a branch that
    # has moved since resolves to something newer than the tip this run recorded.
    # The recipe cache is no defence: every distinct recipe runs its own update,
    # and the halves the partition tries are all distinct recipes. Two trials
    # that both claim "at its tip" would then be testing two different
    # revisions, and the bisect would go on to search the history of one no
    # trial actually used. Put anything that drifted back where the run started.
    for t in "${tips[@]}"; do
      [ "$(locked_rev "$t")" = "${TIP_REV[$t]}" ] && continue
      origin="$(input_origin "$t")"
      slug="${origin%%$'\t'*}"
      if [ -z "$slug" ]; then
        echo "      warning: $t moved during the run and is not a github input," \
          "so this trial tests the newer revision" >&2
        continue
      fi
      pin_input "$t" "$slug" "${TIP_REV[$t]}" || return 1
    done
  fi
  for p in "${pins[@]}"; do
    IFS=: read -r pname pslug prev <<<"$p"
    pin_input "$pname" "$pslug" "$prev" || return 1
  done
  cp "$LOCK" "$cached"
}

# Reset to the baseline, then move every input to its tip. --refresh so a tip
# resolved less than an hour ago (nix's tarball-ttl) is not mistaken for current;
# the whole point of the run is to find out what is actually newest.
update_all() {
  cp "$BASELINE_LOCK" "$LOCK"
  run_flake_update "$LOGDIR/update-all.log" --refresh || {
    echo "error: nix flake update failed" >&2
    cat "$LOGDIR/update-all.log" >&2
    exit 1
  }
}

# The recipe for "everything decided so far", plus whatever extra tokens are
# passed. Read at call time, so it always reflects the current KEPT/PINS.
state_tokens() {
  TOKENS=()
  local n p
  for n in "${KEPT[@]}"; do TOKENS+=("tip:$n"); done
  for p in "${PINS[@]}"; do TOKENS+=("pin:$p"); done
  TOKENS+=("$@")
}

# --- Running nix --------------------------------------------------------------
# Trials take minutes, so silence is indistinguishable from a hang. Default is a
# single self-erasing elapsed-time line on a terminal; -v hands nix the terminal
# instead and keeps the log as a copy.

run_nix() {
  local log="$1" outf="$2" start=$SECONDS rc=0 pid
  shift 2
  if [ "$VERBOSE" -eq 1 ]; then
    # A pipeline rather than a process substitution, so the log is complete by
    # the time the caller reads it back looking for the failure.
    { "$@" 2>&1 >"$outf" | tee -a "$log" >&2; } || rc=$?
  elif [ "$TTY" -eq 1 ]; then
    "$@" >"$outf" 2>>"$log" &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
      # Quiet for the first few seconds: most trials are answered from the .drv
      # cache, and a line that appears and vanishes again is just flicker. Those
      # short trials are also why the poll starts tight — a full second of
      # latency on each of twenty cache hits is a fifth of the run.
      if [ $((SECONDS - start)) -lt 3 ]; then
        sleep 0.2
      else
        printf '\r      · %s' "$(fmt_dur $((SECONDS - start)))"
        sleep 1
      fi
    done
    wait "$pid" || rc=$?
    printf '\r\033[K'
  else
    "$@" >"$outf" 2>>"$log" || rc=$?
  fi
  return "$rc"
}

# --- Trials -------------------------------------------------------------------
# A trial is split into evaluation and build so the two can be cached separately.
# Evaluation yields the target's .drv path, and equal .drv paths mean an
# identical build: an input whose update does not reach the target — a dev-shell
# or checks-only input, most commonly — resolves to a verdict already on record
# and costs nothing at all. Building the .drv directly then skips the second
# evaluation `nix build` on the flake attr would otherwise do.

declare -A DRV_VERDICT DRV_TRIAL DRV_OUT LOCK_CHECKED

abort_if_interrupted() {
  local rc="$1" log="$2"
  if [ "$rc" -gt 128 ] || grep -q 'interrupted by the user' "$log" 2>/dev/null; then
    echo >&2
    echo "interrupted." >&2
    exit 130
  fi
}

# A build that died because the disk filled up or the daemon went away says
# nothing about the inputs, and every trial after it would inherit the same fate.
abort_if_fatal() {
  local log="$1"
  if grep -qaE 'No space left on device|cannot connect to daemon|Disk quota exceeded' "$log"; then
    KEEP_LOGS=1
    echo >&2
    report_error "$log" >&2
    die "the build environment failed, not the inputs — nothing can be concluded"
  fi
}

# Network flakiness would otherwise be recorded as "this revision is broken" and
# hold an input back for the rest of the run, so it is worth one retry.
is_transient() {
  grep -qaE 'unable to download|Couldn.t resolve host|Temporary failure in name resolution|Connection reset by peer|error: unable to load|HTTP error 5[0-9][0-9]|Operation timed out|SSL peer certificate' "$1"
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
# $1 is the label this state is remembered by when a later trial turns out to be
# byte-identical to it.
trial() {
  local label="$1" tag log start=$SECONDS elapsed rc drv attempt

  TRIAL_N=$((TRIAL_N + 1))
  tag="$(printf 't%02d' "$TRIAL_N")"
  log="$LOGDIR/$tag.log"
  : >"$log"
  printf '%s: %s\n' "$tag" "$label" >>"$log"

  EVALS=$((EVALS + 1))
  rc=0
  run_nix "$log" "$WORKDIR/drv" nix path-info --derivation --no-warn-dirty "$TARGET" || rc=$?
  drv="$(head -n1 "$WORKDIR/drv" 2>/dev/null || true)"
  if [ "$rc" -ne 0 ] || [ -z "$drv" ]; then
    abort_if_interrupted "$rc" "$log"
    abort_if_fatal "$log"
    printf '    ✗ evaluation failed (%ds)\n' "$((SECONDS - start))"
    report_error "$log"
    return 1
  fi

  if [ -n "${DRV_VERDICT[$drv]-}" ]; then
    if [ "${DRV_VERDICT[$drv]}" = ok ]; then
      TRIAL_OUT="${DRV_OUT[$drv]}"
      printf '    ✓ builds (identical to %s)\n' "${DRV_TRIAL[$drv]}"
      check_lock "$log" "$start"
      return
    fi
    printf '    ✗ failed (identical to %s)\n' "${DRV_TRIAL[$drv]}"
    return 1
  fi

  DRV_TRIAL[$drv]="$tag"
  for attempt in 1 2; do
    BUILDS=$((BUILDS + 1))
    rc=0
    run_nix "$log" "$WORKDIR/out" \
      nix build --no-link --print-out-paths --no-warn-dirty "$drv^*" || rc=$?
    [ "$rc" -eq 0 ] && break
    abort_if_interrupted "$rc" "$log"
    abort_if_fatal "$log"
    if [ "$attempt" -eq 1 ] && is_transient "$log"; then
      printf '    … network trouble, retrying once\n'
      continue
    fi
    break
  done
  elapsed=$((SECONDS - start))
  if [ "$rc" -ne 0 ]; then
    DRV_VERDICT[$drv]=bad
    printf '    ✗ failed (%ds)\n' "$elapsed"
    report_error "$log"
    return 1
  fi
  DRV_VERDICT[$drv]=ok
  DRV_OUT[$drv]="$(head -n1 "$WORKDIR/out" 2>/dev/null || true)"
  TRIAL_OUT="${DRV_OUT[$drv]}"
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
  run_nix "$log" /dev/null nix flake check --no-warn-dirty "$FLAKE_DIR" || rc=$?
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

# Compose "everything decided so far plus these extra tokens" and build it.
try_state() {
  local label="$1"
  shift
  state_tokens "$@"
  compose "${TOKENS[@]}" || return 1
  trial "$label"
}

# --- Where candidate revisions come from --------------------------------------

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

# The channel a nixpkgs input tracks, as a path in the release bucket. Only
# nixpkgs has one; every other input falls through to the per-day search.
channel_prefix() {
  local owner="${1,,}" repo="${2,,}" ref="$3"
  [ "$owner" = "nixos" ] && [ "$repo" = "nixpkgs" ] || return 1
  case "$ref" in
  nixpkgs-unstable) printf 'nixpkgs/\n' ;;
  nixos-unstable | nixos-unstable-small) printf 'nixos/%s/\n' "${ref#nixos-}" ;;
  nixos-[0-9][0-9].[0-9][0-9] | nixos-[0-9][0-9].[0-9][0-9]-small)
    printf 'nixos/%s/\n' "${ref#nixos-}"
    ;;
  *) return 1 ;;
  esac
}

# Every release ever published under a channel, newest first, as
# "serial<TAB>short-rev<TAB>name". The bucket lists lexicographically, which is
# not chronological — `nixos-26.05.889` sorts after `nixos-26.05.7675` — so the
# ordering comes from the serial in the name, which is a commit count and only
# ever goes up. `marker` skips the decade of releases before the ones that could
# possibly be in range; if that guess is wrong the caller notices, because the
# input's current tip will not be in the list.
s3_releases() {
  local prefix="$1" marker="$2" url out names last
  names=""
  while :; do
    url="https://nix-releases.s3.amazonaws.com/?prefix=$prefix&delimiter=/&max-keys=1000"
    [ -n "$marker" ] && url="$url&marker=$marker"
    out="$(curl -sfL --retry 2 "$url")" || return 1
    last="$(printf '%s' "$out" | grep -o '<Prefix>[^<]*</Prefix>' |
      sed 's|<[^>]*>||g' | tail -n1)"
    names="$names$(printf '%s' "$out" | grep -o '<Prefix>[^<]*</Prefix>' |
      sed 's|<[^>]*>||g; s|/$||; s|.*/||')
"
    printf '%s' "$out" | grep -q '<IsTruncated>true</IsTruncated>' || break
    [ -n "$last" ] || break
    marker="$last"
  done
  printf '%s\n' "$names" |
    sed -nE 's/^((nixos|nixpkgs)-[0-9]+\.[0-9]+(pre|\.)([0-9]+)\.([0-9a-f]{7,}))$/\4\t\5\t\1/p' |
    sort -k1,1nr
}

# Candidate list for one input, newest first. Index 0 is always the tip itself:
# it was rejected on top of a smaller set of updates than the one in force now,
# so it deserves a re-test — and if nothing has changed since, the .drv cache
# answers for free. The far end of the list is the baseline, which is known good
# and is represented by the index one past the end rather than by an entry.
CAND_LABEL=()
CAND_SPEC=()
declare -A CAND_REV_MEMO

build_candidates() {
  local name="$1" slug="$2" ref="$3" prefix short relname ts day i
  local owner="${slug%%/*}" repo="${slug#*/}"
  CAND_LABEL=("$(day_of "${TIP_TS[$name]}") (tip)")
  CAND_SPEC=("rev:${TIP_REV[$name]}")

  if prefix="$(channel_prefix "$owner" "$repo" "$ref")"; then
    local -a rel_short=() rel_name=()
    local marker="" nameprefix="nixos-" chanver
    [ "$prefix" = "nixpkgs/" ] && nameprefix="nixpkgs-"
    # The marker skips the decade of releases that could not possibly be in
    # range. A stable channel names its own version in every release it
    # publishes (nixos-25.05.7675.abcdef1), so there the marker can be exact.
    # Only a rolling channel has to be guessed at, and there the version in the
    # name tracks the calendar — 26.05pre… through the first half of 2026 — so a
    # year before the tip is more history than --max-days can ever reach. Base
    # 10 is explicit because `%y` yields a leading zero one decade in ten.
    #
    # Guessing for a stable channel as well used to skip its listing whole once
    # the channel was more than a calendar year old: every nixos-25.05.* key
    # sorts before a "nixos-26." marker, so the tip was not in the list and the
    # run dropped silently back to a per-day commit search — a search of
    # revisions Hydra never built, which is the one thing channel releases are
    # here to avoid.
    case "$ref" in
    nixos-[0-9][0-9].[0-9][0-9] | nixos-[0-9][0-9].[0-9][0-9]-small)
      chanver="${ref#nixos-}"
      marker="$prefix$nameprefix${chanver%-small}."
      ;;
    *)
      marker="$prefix$nameprefix$((10#$(date -u -d "@${TIP_TS[$name]}" +%y) - 1))."
      ;;
    esac
    local found=-1 idx=0
    while IFS=$'\t' read -r _ short relname; do
      rel_short+=("$short")
      rel_name+=("$relname")
      [ "${TIP_REV[$name]#"$short"}" != "${TIP_REV[$name]}" ] && found="$idx"
      idx=$((idx + 1))
    done < <(s3_releases "$prefix" "$marker" || true)

    if [ "$found" -ge 0 ]; then
      for ((i = found + 1; i < ${#rel_short[@]}; i++)); do
        [ "${#CAND_SPEC[@]}" -lt "$MAX_DAYS" ] || break
        # The baseline ends the list: it is the known-good far end, not a candidate.
        [ "${BASE_REV[$name]#"${rel_short[i]}"}" != "${BASE_REV[$name]}" ] && break
        CAND_LABEL+=("${rel_name[i]}")
        CAND_SPEC+=("chan:$prefix:${rel_name[i]}")
      done
      CAND_KIND="channel releases"
      return 0
    fi
    printf '    (tip is not a published %s release; falling back to commits)\n' "$ref"
  fi

  # One candidate per day, from the day before the tip back to the baseline's own
  # day. Days are the right granularity for anything that is not a channel: it is
  # the unit a breakage is actually measured in ("home-manager broke yesterday"),
  # and it keeps the list to a handful instead of the thousands of commits
  # between two lock positions. Revisions are resolved against the tip's own
  # history rather than the branch, so a branch that moves mid-run cannot change
  # what is being searched.
  ts=$((TIP_TS[$name] - 86400))
  while [ "$ts" -ge "${BASE_TS[$name]}" ] && [ "${#CAND_SPEC[@]}" -lt "$MAX_DAYS" ]; do
    day="$(day_of "$ts")"
    CAND_LABEL+=("$day")
    CAND_SPEC+=("day:$slug:${TIP_REV[$name]}:$day")
    ts=$((ts - 86400))
  done
  CAND_KIND="daily commits"
}

# Turn candidate $1 into a full revision, memoised. Resolved on demand because
# the search only ever visits a logarithmic number of them, so resolving the
# whole list up front would spend sixty requests to use six.
resolve_cand() {
  local i="$1"
  local spec="${CAND_SPEC[$i]}" out="" pfx nm slug ref day
  if [ -n "${CAND_REV_MEMO[$i]-}" ]; then
    CAND_REV="${CAND_REV_MEMO[$i]}"
    [ "$CAND_REV" != - ]
    return
  fi
  case "$spec" in
  rev:*) out="${spec#rev:}" ;;
  chan:*)
    IFS=: read -r _ pfx nm <<<"$spec"
    out="$(curl -sfL --retry 2 "https://releases.nixos.org/$pfx$nm/git-revision" || true)"
    ;;
  day:*)
    IFS=: read -r _ slug ref day <<<"$spec"
    out="$(gh_json "repos/$slug/commits?sha=$ref&until=${day}T23:59:59Z&per_page=1" |
      jq -r '.[0].sha // empty' 2>/dev/null || true)"
    ;;
  esac
  out="$(printf '%s' "$out" | tr -dc '0-9a-f')"
  [[ "$out" =~ ^[0-9a-f]{40}$ ]] || out=-
  CAND_REV_MEMO[$i]="$out"
  CAND_REV="$out"
  [ "$out" != - ]
}

# Verdicts are cached per revision as well as per .drv: consecutive candidate
# days often resolve to the same commit (a quiet weekend on the branch).
# REV_TS records how old each tried revision turned out to be, so the result can
# be compared against the baseline at the end.
declare -A REV_VERDICT REV_TS

try_cand() {
  local name="$1" slug="$2" i="$3" rev rc=0 lookup=0
  # Index 0 carries the tip's revision in the candidate itself; everything else
  # has to be asked for. Only those count towards "could anything be resolved at
  # all", or an unreachable GitHub would still look like one successful lookup.
  case "${CAND_SPEC[$i]}" in rev:*) ;; *) lookup=1 ;; esac
  if ! resolve_cand "$i"; then
    [ "$lookup" -eq 1 ] && LOOKUPS_FAILED=$((LOOKUPS_FAILED + 1))
    printf '    %-38s (could not resolve; skipping)\n' "${CAND_LABEL[$i]}"
    return 1
  fi
  [ "$lookup" -eq 1 ] && LOOKUPS_OK=$((LOOKUPS_OK + 1))
  rev="$CAND_REV"
  if [ -n "${REV_VERDICT[$rev]-}" ]; then
    printf '    %-38s %s  (already known: %s)\n' \
      "${CAND_LABEL[$i]}" "${rev:0:10}" "${REV_VERDICT[$rev]}"
    [ "${REV_VERDICT[$rev]}" = ok ]
    return
  fi
  printf '    %-38s %s\n' "${CAND_LABEL[$i]}" "${rev:0:10}"
  try_state "bisect $name@${rev:0:8}" "pin:$name:$slug:$rev" || rc=$?
  # Read back from the lock the trial actually used, so the age is the composed
  # one and not something inferred from the candidate's label.
  REV_TS[$rev]="$(locked_ts "$name")"
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

declare -A BASE_REV BASE_TS
while IFS=$'\t' read -r name rev ts; do
  BASE_REV[$name]="$rev"
  BASE_TS[$name]="$ts"
done < <(lock_revs "$BASELINE_LOCK")

# Checked against the baseline rather than the tips so a typo costs nothing.
for name in "${ONLY[@]}"; do
  [ -n "${BASE_REV[$name]-}" ] ||
    die "no input named '$name' in the $BASELINE lock (have: ${!BASE_REV[*]})"
done

# --- What is even available ---------------------------------------------------
echo "Checking for input updates..."
update_all
declare -A TIP_REV TIP_TS
while IFS=$'\t' read -r name rev ts; do
  TIP_REV[$name]="$rev"
  TIP_TS[$name]="$ts"
done < <(lock_revs)

wanted() {
  local n
  [ "${#ONLY[@]}" -eq 0 ] && return 0
  for n in "${ONLY[@]}"; do [ "$n" = "$1" ] && return 0; done
  return 1
}

# The tip lock is the one that has every input flake.nix declares; an input added
# since the baseline was committed is simply not in the baseline at all. There is
# no older revision to fall back to for those, so they ride along at their tip in
# every trial and are neither searched nor held back.
UPDATABLE=()
for name in $(printf '%s\n' "${!TIP_REV[@]}" | sort); do
  if [ -z "${BASE_REV[$name]-}" ]; then
    printf '  + %-24s new input, always at its tip (%s)\n' "$name" \
      "$(day_of "${TIP_TS[$name]}")"
  elif [ "${BASE_REV[$name]}" = "${TIP_REV[$name]}" ]; then
    printf '  = %-24s unchanged (%s)\n' "$name" "$(day_of "${BASE_TS[$name]}")"
  elif ! wanted "$name"; then
    printf '  - %-24s update available, not selected\n' "$name"
  else
    UPDATABLE+=("$name")
    printf '  ↻ %-24s %s → %s\n' "$name" \
      "$(day_of "${BASE_TS[$name]}")" "$(day_of "${TIP_TS[$name]}")"
  fi
done
echo

if [ "${#UPDATABLE[@]}" -eq 0 ]; then
  # Nothing to search means nothing was verified either, so the working tree is
  # left exactly as found rather than being overwritten with an untested lock.
  cp "$ORIG_LOCK" "$LOCK"
  SUCCESS=1
  echo "Nothing to search — flake.lock untouched."
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

# The all-at-tips lock is exactly what `compose` would compute for the full set,
# and it has just been computed, so hand it to the cache instead of refetching.
if [ "${#ONLY[@]}" -eq 0 ]; then
  ALL_TOKENS=()
  for name in "${UPDATABLE[@]}"; do ALL_TOKENS+=("tip:$name"); done
  cp "$LOCK" "$LOCKCACHE/$(lock_key "${ALL_TOKENS[@]}").lock"
fi

echo "Verifying the baseline builds..."
cp "$BASELINE_LOCK" "$LOCK"
if ! trial "baseline"; then
  KEEP_LOGS=1
  echo >&2
  echo "error: the $BASELINE baseline does not build on its own." >&2
  echo "Nothing can be concluded about the inputs until that is fixed." >&2
  exit 1
fi
BASELINE_OUT="$TRIAL_OUT"
echo

# --- Which inputs can reach their tips ----------------------------------------
# Binary partitioning rather than one trial per input: the whole set is tried
# first (the common case is that it just works, and that is then the only build),
# and a set that fails is split in half and each half retried on top of whatever
# has already been accepted. One culprit among eleven inputs costs about seven
# trials instead of eleven, and because every trial is "what we have kept so far,
# plus this half", an input that only breaks in combination with another is still
# caught — there is no separate combine-and-narrow pass.
#
# The result is a maximal set, not necessarily the largest one: an input rejected
# early is not retried against the larger set that later accumulates. That is
# what the bisect's index 0 — the tip — is for.
absorb() {
  local -a list=("$@")
  local n="${#list[@]}" half x
  [ "$n" -gt 0 ] || return 0

  local -a add=()
  for x in "${list[@]}"; do add+=("tip:$x"); done
  if [ "$n" -eq "${#UPDATABLE[@]}" ]; then
    printf '  all %d input(s) at their tips\n' "$n"
  else
    printf '  keeping %d, trying: %s\n' "${#KEPT[@]}" "${list[*]}"
  fi
  if try_state "tips: ${list[*]}" "${add[@]}"; then
    KEPT+=("${list[@]}")
    return 0
  fi
  if [ "$n" -eq 1 ]; then
    RED+=("${list[0]}")
    return 0
  fi
  half=$((n / 2))
  absorb "${list[@]:0:half}"
  absorb "${list[@]:half}"
}

echo "Searching for the newest set of inputs that build together..."
absorb "${UPDATABLE[@]}"
echo

# --- Bisect the held-back inputs ----------------------------------------------
# Everything above chose only between "input at baseline" and "input at tip", so
# a red input drops all the way back to the last committed lock — often far older
# than the newest revision that would actually have worked.
#
# Candidates run newest-first, and the search starts at the newest and walks
# back, so a breakage introduced yesterday costs a single build.
#
# The first --linear candidates are checked one at a time. That part needs no
# assumptions at all: everything newer has been tried and failed, so the first
# one that builds is provably the newest that does. Past that the stride doubles
# (1, 2, 4, 8…) and the bracket that straddles the boundary is binary-searched,
# which costs ~2·log2(candidates) instead of one build per candidate.
#
# Only the skipping part assumes the boundary is monotone — that once a revision
# builds, older ones do too. Breakages get introduced and later fixed, so a
# window can genuinely read bad-good-bad-good from the tip backwards, and a
# search that skips can land on the older good stretch and throw away the newer
# one. Scanning the newest candidates one by one is what buys that back, and it
# is worth the builds precisely there: a day of freshness lost when you are one
# day behind matters, the same day lost when you are forty behind does not.
# `--linear 0` skips from the start, a large `--linear` never skips.
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

    CAND_REV_MEMO=()
    CAND_KIND=""
    LOOKUPS_OK=0
    LOOKUPS_FAILED=0
    build_candidates "$name" "$slug" "$ref"
    n="${#CAND_SPEC[@]}"
    # The baseline is the known-good far end of the range, one index past the
    # list. Everything in between is what the search actually visits.
    REV_VERDICT["${BASE_REV[$name]}"]=ok
    printf '  %s: %d candidate(s) from %s, newest first\n' "$name" "$n" "$CAND_KIND"

    lo=-1 # newest index known to fail
    hi="$n"
    step=1
    idx=0
    probed=0
    while [ "$idx" -lt "$n" ]; do
      if try_cand "$name" "$slug" "$idx"; then
        hi="$idx"
        break
      fi
      lo="$idx"
      # One at a time while a build still buys a day of freshness worth having,
      # counted in probes made rather than in the index reached. The two are the
      # same thing only until the stride grows, but the count is what --linear
      # is defined as — and testing the already-advanced index instead left the
      # stride at 1 for one step longer than asked, so `--linear 0` and
      # `--linear 1` both still checked two candidates and there was no way to
      # ask for no linear prefix at all.
      probed=$((probed + 1))
      if [ "$probed" -ge "$LINEAR" ]; then step=$((step * 2)); fi
      idx=$((idx + step))
    done
    # Narrow (lo, hi] down to the newest revision that still builds. hi may still
    # be the baseline here, which is what makes the untested tail of a fully
    # failed walk get searched rather than written off.
    while [ $((hi - lo)) -gt 1 ]; do
      mid=$(((lo + hi) / 2))
      if try_cand "$name" "$slug" "$mid"; then
        hi="$mid"
      else
        lo="$mid"
      fi
    done

    # A search in which every lookup failed found nothing because it could not
    # ask, not because nothing builds. Saying "no revision newer than the
    # baseline builds" there would be asserting a build verdict about revisions
    # that were never named, let alone built — and it would read as "give up on
    # this input" when the honest advice is "try again when GitHub answers".
    if [ "$LOOKUPS_FAILED" -gt 0 ] && [ "$LOOKUPS_OK" -eq 0 ]; then
      NORESOLVE+=("$name")
      printf '    → could not resolve any candidate revision; staying at baseline\n'
      continue
    fi

    if [ "$hi" -lt "$n" ]; then
      resolve_cand "$hi" || die "lost the revision the bisect settled on for $name"
      rev="$CAND_REV"
    else
      rev="${BASE_REV[$name]}"
    fi
    # The search can land at or below the baseline: a day-granular walk's oldest
    # candidate is the day the baseline was locked, and a channel list runs past
    # the baseline entirely when the baseline is not itself a published release.
    # Older than what we started with is not an improvement and must not become
    # a pin, so the test is on age and not just on revision equality.
    if [ "$hi" -ge "$n" ] || [ "$rev" = "${BASE_REV[$name]}" ] ||
      [ "${REV_TS[$rev]:-0}" -le "${BASE_TS[$name]}" ]; then
      printf '    → nothing newer than the baseline builds; staying at baseline\n'
      continue
    fi
    PINS+=("$name:$slug:$rev")
    BISECTED+=("$name"$'\t'"${CAND_LABEL[$hi]}"$'\t'"$rev")
    # The label is the candidate that was probed, which for a daily search is a
    # day and not the revision's own date — the summary at the end reports the
    # date the lock actually ends up with.
    printf '    → newest working candidate: %s → %s\n' "${CAND_LABEL[$hi]}" "${rev:0:10}"
  done
  echo
fi

# --- Final verification -------------------------------------------------------
# Recompose the winning combination so the lock on disk is exactly what gets
# reported, then build it as a whole. The steps above each verified a state, but
# the composition of all of them is its own state, and it is the one being
# written. Thanks to the .drv cache this is usually free.
state_tokens
compose "${TOKENS[@]}" || die "could not recompose the winning combination"

if [ "${#KEPT[@]}" -gt 0 ] || [ "${#BISECTED[@]}" -gt 0 ]; then
  echo "Verifying the result as a whole..."
  if trial "final"; then
    FINAL_OUT="$TRIAL_OUT"
  else
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
    [ "${b%%$'\t'*}" = "$name" ] && pinned=1
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
  # Dates come from the lock that was actually written, so the report cannot
  # describe something other than what is on disk.
  declare -A NEW_TS
  while IFS=$'\t' read -r name rev ts; do NEW_TS[$name]="$ts"; done < <(lock_revs)
  for name in "${KEPT[@]}"; do
    printf '  at tip     %-22s %s → %s\n' "$name" \
      "$(day_of "${BASE_TS[$name]}")" "$(day_of "${NEW_TS[$name]}")"
  done
  for b in "${BISECTED[@]}"; do
    IFS=$'\t' read -r bname _ brev <<<"$b"
    printf '  bisected   %-22s %s → %s (%s), tip was %s\n' \
      "$bname" "$(day_of "${BASE_TS[$bname]}")" "$(day_of "${NEW_TS[$bname]}")" \
      "${brev:0:10}" "$(day_of "${TIP_TS[$bname]}")"
  done
fi

for name in "${STILL_BACK[@]}"; do
  printf '  held back  %-22s stays at %s\n' "$name" "$(day_of "${BASE_TS[$name]}")"
done

# What the update actually amounts to, in packages rather than in revisions.
# Both closures are in the store already, so this is a local comparison.
if [ -n "$BASELINE_OUT" ] && [ -n "$FINAL_OUT" ] && [ "$BASELINE_OUT" != "$FINAL_OUT" ] &&
  nix store diff-closures "$BASELINE_OUT" "$FINAL_OUT" >"$WORKDIR/diff" 2>/dev/null &&
  [ -s "$WORKDIR/diff" ]; then
  echo
  echo "Closure changes vs the baseline:"
  head -n 25 "$WORKDIR/diff" | sed 's/^/  /'
  lines="$(wc -l <"$WORKDIR/diff")"
  [ "$lines" -gt 25 ] && printf '  … and %d more\n' "$((lines - 25))"
fi

printf '\nDone in %s (%d build(s), %d evaluation(s)).\n' \
  "$(fmt_dur $((SECONDS - RUN_START)))" "$BUILDS" "$EVALS"

if [ "${#STILL_BACK[@]}" -gt 0 ]; then
  echo
  if [ "$BISECT" -eq 0 ]; then
    echo "These stay at the baseline. Re-run without --no-bisect to search their"
    echo "history for the newest revision that does build."
  else
    # Two different reasons an input can be left behind, and only one of them is
    # a statement about the input.
    SEARCHED=()
    for name in "${STILL_BACK[@]}"; do
      unresolved=0
      for b in "${NORESOLVE[@]}"; do [ "$b" = "$name" ] && unresolved=1; done
      [ "$unresolved" -eq 0 ] && SEARCHED+=("$name")
    done
    if [ "${#SEARCHED[@]}" -gt 0 ]; then
      echo "No revision newer than the baseline builds for: ${SEARCHED[*]}"
      echo "Re-run in a few days, or fix the breakage in the config by hand."
    fi
    if [ "${#NORESOLVE[@]}" -gt 0 ]; then
      echo "No candidate revision could be resolved for: ${NORESOLVE[*]}"
      echo "That is GitHub being unreachable or rate-limited, not a verdict on those"
      echo "inputs — nothing was built for them. Re-run when it answers again."
    fi
  fi
fi
