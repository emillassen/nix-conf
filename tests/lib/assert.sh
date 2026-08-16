# shellcheck shell=bash
# Assertions. Every one of them reports the case, the label, what was expected
# and what actually happened, then keeps going: a case that checks eight things
# should tell you about all eight failures in one run, not make you fix them one
# per invocation.
#
# Sourced by lib/harness.sh, never on its own.

FAILURES=0
CHECKS=0

# Multi-line values are indented and fenced so a trailing newline, a stray \r or
# an empty string are all visibly different from each other in the output.
_show() {
  local label="$1" value="$2"
  if [[ "$value" == *$'\n'* ]]; then
    printf '    %s: |\n' "$label"
    printf '%s\n' "$value" | sed 's/^/      /'
  else
    printf '    %s: %q\n' "$label" "$value"
  fi
}

fail() {
  local label="$1"
  shift
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$label"
  local line
  for line in "$@"; do printf '    %s\n' "$line"; done
}

pass() { :; }

_check() {
  CHECKS=$((CHECKS + 1))
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  _check
  [[ "$expected" == "$actual" ]] && return 0
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$label"
  _show expected "$expected"
  _show actual "$actual"
}

assert_ne() {
  local label="$1" unexpected="$2" actual="$3"
  _check
  [[ "$unexpected" != "$actual" ]] && return 0
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$label"
  _show 'expected anything but' "$unexpected"
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  _check
  [[ "$haystack" == *"$needle"* ]] && return 0
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$label"
  _show 'expected to contain' "$needle"
  _show 'actual' "$haystack"
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  _check
  [[ "$haystack" != *"$needle"* ]] && return 0
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$label"
  _show 'expected NOT to contain' "$needle"
  _show 'actual' "$haystack"
}

assert_matches() {
  local label="$1" string="$2" regex="$3"
  _check
  [[ "$string" =~ $regex ]] && return 0
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$label"
  _show 'expected to match' "$regex"
  _show 'actual' "$string"
}

# Exit status of the last run_* helper.
assert_exit() {
  local label="$1" expected="$2"
  _check
  [[ "$STATUS" == "$expected" ]] && return 0
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$label"
  _show 'expected exit' "$expected"
  _show 'actual exit' "$STATUS"
  _show 'stdout' "$STDOUT"
  _show 'stderr' "$STDERR"
}

assert_file_exists() {
  local label="$1" path="$2"
  _check
  [[ -e "$path" ]] && return 0
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$label"
  _show 'expected to exist' "$path"
  _show 'siblings' "$(ls -A "$(dirname "$path")" 2>&1 || true)"
}

assert_file_missing() {
  local label="$1" path="$2"
  _check
  [[ ! -e "$path" ]] && return 0
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$label"
  _show 'expected NOT to exist' "$path"
}

# Byte-for-byte, which is what "the working tree was left exactly as found"
# actually means.
assert_files_identical() {
  local label="$1" a="$2" b="$3"
  _check
  if cmp -s "$a" "$b"; then return 0; fi
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$label"
  _show 'expected identical' "$a == $b"
  _show 'diff' "$(diff -u "$a" "$b" 2>&1 | head -n 20 || true)"
}

assert_file_contains() {
  local label="$1" path="$2" needle="$3"
  _check
  if [[ -f "$path" ]] && grep -qF -- "$needle" "$path"; then return 0; fi
  FAILURES=$((FAILURES + 1))
  printf '  FAIL %s\n' "$label"
  _show 'file' "$path"
  _show 'expected to contain' "$needle"
  _show 'contents' "$(cat "$path" 2>&1 || true)"
}
