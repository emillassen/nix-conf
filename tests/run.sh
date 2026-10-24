#!/usr/bin/env bash
#
# Runs every case under tests/cases/. Offline and hermetic: nothing here talks
# to the network, and every case works in its own temp directory.
#
#   ./tests/run.sh                 everything
#   ./tests/run.sh flake           only cases whose path matches "flake"
#   ./tests/run.sh drtv-dl/07      a single case
#   KEEP_TMP=1 ./tests/run.sh …    leave each case's temp dir behind
#   CASE_TIMEOUT=300 ./tests/run.sh   per-case limit in seconds (default 120)
#
# Exits non-zero if any case fails.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
export TESTS_DIR REPO_DIR

cases=()
while IFS= read -r f; do cases+=("$f"); done < <(
  find "$TESTS_DIR/cases" -type f -name '*.sh' | sort
)

if [[ $# -gt 0 ]]; then
  filtered=()
  for f in "${cases[@]}"; do
    for pat in "$@"; do
      [[ "$f" == *"$pat"* ]] && {
        filtered+=("$f")
        break
      }
    done
  done
  cases=(${filtered[@]+"${filtered[@]}"})
fi

if [[ ${#cases[@]} -eq 0 ]]; then
  echo "no cases matched" >&2
  exit 1
fi

pass=0
fail=0
failed=()
start=$SECONDS

for f in "${cases[@]}"; do
  rel="${f#"$TESTS_DIR"/cases/}"
  printf '\n== %s\n' "$rel"
  # A deadline per case: the cases exercise locking and waiting, and a
  # regression there (a lock that is never released, a wait that never ends)
  # would otherwise hang the whole run with no summary at all. --kill-after,
  # since the case's EXIT trap gets the TERM first and a hung child may not.
  rc=0
  timeout --kill-after=10 "${CASE_TIMEOUT:-120}" bash "$f" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass=$((pass + 1))
  else
    [[ "$rc" -eq 124 || "$rc" -eq 137 ]] &&
      printf '  FAIL %s: no result after %ss\n' "$rel" "${CASE_TIMEOUT:-120}"
    fail=$((fail + 1))
    failed+=("$rel")
  fi
done

printf '\n---------------------------------------------\n'
printf '%d passed, %d failed, in %ds\n' "$pass" "$fail" "$((SECONDS - start))"
if [[ "$fail" -gt 0 ]]; then
  printf 'failed cases:\n'
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
