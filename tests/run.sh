#!/usr/bin/env bash
#
# Runs every case under tests/cases/. Offline and hermetic: nothing here talks
# to the network, and every case works in its own temp directory.
#
#   ./tests/run.sh                 everything
#   ./tests/run.sh flake           only cases whose path matches "flake"
#   ./tests/run.sh drtv/07         a single case
#   KEEP_TMP=1 ./tests/run.sh …    leave each case's temp dir behind
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
  if bash "$f"; then
    pass=$((pass + 1))
  else
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
