#!/usr/bin/env bash
#
# Report — or, when asked, remove — the scratch directories a working session
# leaves behind in /tmp.
#
#   check-leftovers.sh                          report everything, oldest first
#   check-leftovers.sh --since '3 hours ago'    split it into "this session" and older
#   check-leftovers.sh --since '3 hours ago' --remove
#
# Reporting is the default and removal has to be asked for, because none of
# these patterns belongs exclusively to the test suite: flake-up-safe.sh keeps
# its working directory on purpose whenever a run fails or holds an input back,
# and Emil runs it — and standardebooks-dl — for real. Deleting by pattern alone
# would take his logs with it. --since is therefore the safety mechanism: pass
# the time the session started, and only directories *created* since then are
# this session's. Creation, not modification: a real run that started before
# the session and wrote a file into its directory during it has a fresh mtime
# and is still not this session's. A directory some live process is working in
# (its cwd, or a file it has open) is never removed either, whatever its age.
#
# `tmp.XXXXXXXXXX` directories are listed but never removed even with --remove:
# that is plain mktemp's default name, shared by every program on the machine,
# so they are for a human to look at.
set -euo pipefail

since=""
remove=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      since="${2:?--since needs a date understood by date -d}"
      shift 2
      ;;
    --remove)
      remove=1
      shift
      ;;
    -h | --help)
      sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//; $d'
      exit 0
      ;;
    *)
      echo "check-leftovers.sh: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$remove" == 1 && -z "$since" ]]; then
  echo "check-leftovers.sh: --remove requires --since; refusing to delete by pattern alone" >&2
  exit 2
fi

# The suite's own shapes, and the shapes the scripts under test make.
patterns=('flake-up-safe.*' 'shtest.*')

cutoff=""
if [[ -n "$since" ]]; then
  cutoff="$(date -d "$since" +%s)" || {
    echo "check-leftovers.sh: --since: date -d cannot read '$since'" >&2
    exit 2
  }
fi

# Whether some process (of this user's - the only ones /proc lets us read) has
# its working directory, or an open file, inside $1.
in_use() {
  local l t
  for l in /proc/[0-9]*/cwd /proc/[0-9]*/fd/*; do
    t="$(readlink "$l" 2>/dev/null)" || continue
    [[ "$t" == "$1" || "$t" == "$1"/* ]] && return 0
  done
  return 1
}

# Paths travel NUL-delimited into arrays and are never parsed back out of the
# report text: a name with a newline in it otherwise turned into two lines, the
# second of which `rm -rf` took for a path of its own.
mine_paths=()
theirs_paths=()
while IFS= read -r -d '' p; do
  born="$(stat -c %W -- "$p" 2>/dev/null || echo 0)"
  if [[ -z "$cutoff" ]]; then
    mine_paths+=("$p")
  elif [[ "$born" -gt 0 && "$born" -ge "$cutoff" ]] && ! in_use "$p"; then
    mine_paths+=("$p")
  else
    # birth time 0 is a filesystem that does not record one: not provably ours
    theirs_paths+=("$p")
  fi
done < <(for pat in "${patterns[@]}"; do
  find /tmp -maxdepth 1 -mindepth 1 -name "$pat" -print0 2>/dev/null || true
done)

show() {
  local p
  for p in "$@"; do printf '%s  %q\n' "$(stat -c %w -- "$p" 2>/dev/null | cut -c1-19)" "$p"; done | sort
}
mine="$(show ${mine_paths[@]+"${mine_paths[@]}"})"
theirs="$(show ${theirs_paths[@]+"${theirs_paths[@]}"})"

count() {
  if [[ -z "$1" ]]; then
    echo 0
  else
    grep -c '' <<<"$1"
  fi
}

indent() { sed 's/^/  /' <<<"$1"; }

printf 'leftovers%s: %s\n' "${since:+ created since $since}" "$(count "$mine")"
[[ -n "$mine" ]] && indent "$mine"
if [[ -n "$theirs" ]]; then
  printf 'older than that, or in use, left alone: %s\n' "$(count "$theirs")"
  indent "$theirs"
fi

# Never removed: plain mktemp's default name is shared with everything else on
# the machine, and one of these was once a real sitemap from a killed run.
unattributed="$(find /tmp -maxdepth 1 -name 'tmp.??????????' -printf '%T+  %p\n' 2>/dev/null | sort || true)"
if [[ -n "$unattributed" ]]; then
  printf 'unattributable (mktemp default names) - inspect by hand, never auto-removed: %s\n' \
    "$(count "$unattributed")"
  indent "$unattributed"
fi

if [[ "$remove" == 1 && ${#mine_paths[@]} -gt 0 ]]; then
  for p in "${mine_paths[@]}"; do
    # find was asked for /tmp's own children; anything else is a bug, not a target
    [[ "$p" == /tmp/* && "${p#/tmp/}" != */* ]] || {
      echo "check-leftovers.sh: refusing to remove $p" >&2
      continue
    }
    rm -rf -- "$p"
  done
  printf 'removed %s\n' "${#mine_paths[@]}"
fi
