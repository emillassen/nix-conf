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
# the time the session started and nothing older is at risk.
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

list() {
  local pat newer=("$@")
  for pat in "${patterns[@]}"; do
    find /tmp -maxdepth 1 -name "$pat" "${newer[@]}" -printf '%T+  %p\n' 2>/dev/null || true
  done | sort
}

if [[ -n "$since" ]]; then
  mine="$(list -newermt "$since")"
  theirs="$(list ! -newermt "$since")"
else
  mine="$(list)"
  theirs=""
fi

count() {
  if [[ -z "$1" ]]; then
    echo 0
  else
    grep -c '' <<<"$1"
  fi
}

indent() { printf '  %s\n' "$@"; }

printf 'leftovers%s: %s\n' "${since:+ since $since}" "$(count "$mine")"
[[ -n "$mine" ]] && indent "$mine"
if [[ -n "$theirs" ]]; then
  printf 'older than that, left alone: %s\n' "$(count "$theirs")"
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

if [[ "$remove" == 1 && -n "$mine" ]]; then
  while IFS= read -r line; do rm -rf -- "${line#*  }"; done <<<"$mine"
  printf 'removed %s\n' "$(count "$mine")"
fi
