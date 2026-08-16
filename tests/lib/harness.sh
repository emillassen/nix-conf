# shellcheck shell=bash
# Shared harness: temp dirs, PATH assembly, stub wiring, and the preamble
# synthesis that makes the two pkgs/ fragments runnable at all.
#
# A case file starts with:
#
#   . "${TESTS_DIR:?}/lib/harness.sh"
#   test_init "what this case is about"
#
# and ends when it ends; the EXIT trap reports and sets the status.

set -uo pipefail

# --- Where things are -----------------------------------------------------------
TESTS_DIR="${TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_DIR="${REPO_DIR:-$(cd "$TESTS_DIR/.." && pwd)}"
STUBS_SRC="$TESTS_DIR/stubs"

FLAKE_UP_SAFE="$REPO_DIR/scripts/flake-up-safe.sh"
SEDL="$REPO_DIR/pkgs/standardebooks-dl/standardebooks-dl.sh"
DRTVDL="$REPO_DIR/pkgs/drtv-dl/drtv-dl.sh"

# shellcheck source=./assert.sh
. "$TESTS_DIR/lib/assert.sh"

# writeShellApplication puts the script under whatever bash nixpkgs built it
# with; the host's bash is that same 5.x, and using it keeps the suite runnable
# from a plain checkout without a store path baked in.
HARNESS_BASH="${HARNESS_BASH:-$(command -v bash)}"

# --- Real tools -----------------------------------------------------------------
# Everything the scripts use that is *not* being faked has to be genuinely
# present, or a green case only proves the stub agreed with itself. unzip in
# particular is a runtimeInput of standardebooks-dl and is usually not on an
# interactive PATH here, so fall back to the store copy rather than skipping the
# epub cases — a skipped case is a hole in the suite that reads as a pass.
_find_real_tool() {
  local tool="$1" p
  if p="$(command -v "$tool" 2>/dev/null)"; then
    printf '%s\n' "$p"
    return 0
  fi
  for p in /nix/store/*-"$tool"-*/bin/"$tool"; do
    [[ -x "$p" ]] && {
      printf '%s\n' "$p"
      return 0
    }
  done
  return 1
}

require_tool() {
  local tool p
  for tool in "$@"; do
    if p="$(_find_real_tool "$tool")"; then
      ln -sf "$p" "$REALBIN/$tool"
    else
      fail "harness: required tool '$tool' not found" \
        "the case cannot run without it; install it or run the suite in 'nix develop'"
      exit 1
    fi
  done
}

# --- Case lifecycle ---------------------------------------------------------------
CASE_NAME=""
TMP=""
STUBDIR=""
STUBLOG=""
REALBIN=""
STATUS=0
STDOUT=""
STDERR=""

test_init() {
  CASE_NAME="${1:-${BASH_SOURCE[1]##*/}}"
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/shtest.XXXXXX")"
  STUBDIR="$TMP/stubs"
  STUBLOG="$TMP/stublog"
  REALBIN="$TMP/realbin"
  mkdir -p "$STUBDIR" "$STUBLOG" "$REALBIN"
  export STUBLOG
  # Everything the case runs makes its own scratch directory with mktemp, and
  # flake-up-safe.sh deliberately *keeps* one whenever a run fails or holds an
  # input back — which most of its cases do on purpose. Pointing TMPDIR inside
  # the case's own directory means those are cleaned up with it instead of
  # leaving a few hundred directories in /tmp behind a full run. Set after $TMP
  # exists, since $TMP was itself made under the old TMPDIR.
  export TMPDIR="$TMP/tmp"
  mkdir -p "$TMPDIR"
  # A stub that needs the genuine article (the date stub delegates every
  # formatting job to it) reaches it through here, never through PATH — PATH is
  # where the stub itself lives.
  export HOST_PATH="$REALBIN:$PATH"
  # Belt to the stubs' braces: if a case ever reaches a tool we forgot to fake,
  # the network attempt fails fast and loudly instead of quietly succeeding and
  # making the suite depend on dr.dk being up.
  export http_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9
  export all_proxy=http://127.0.0.1:9 no_proxy=""
  trap _test_finish EXIT
}

_test_finish() {
  local rc=$?
  # An unexpected non-zero from the case body itself (a typo, a missing file) is
  # a failure of the case, not a pass, so it has to be reported as one.
  if [[ "$rc" -ne 0 && "$FAILURES" -eq 0 ]]; then
    printf '  FAIL %s: case script exited %d before finishing\n' "$CASE_NAME" "$rc"
    FAILURES=1
  fi
  if [[ -n "$TMP" && -d "$TMP" && "${KEEP_TMP:-0}" == 0 ]]; then
    rm -rf "$TMP"
  elif [[ -n "$TMP" ]]; then
    printf '  (tmp kept: %s)\n' "$TMP"
  fi
  if [[ "$FAILURES" -gt 0 ]]; then
    printf '  %d/%d checks failed\n' "$FAILURES" "$CHECKS"
    exit 1
  fi
  printf '  %d checks ok\n' "$CHECKS"
  exit 0
}

# --- Stubs -------------------------------------------------------------------------
# Stubs are copied, not symlinked: a stub reads its behaviour out of
# $STUBLOG/../ scenario files, and copying keeps a case free to patch one.
use_stubs() {
  local name
  for name in "$@"; do
    [[ -f "$STUBS_SRC/$name" ]] || {
      fail "harness: no stub named '$name'"
      exit 1
    }
    install -m 0755 "$STUBS_SRC/$name" "$STUBDIR/$name"
  done
}

# A stub that is nothing but a recording of its own argv, for tools a case only
# needs to prove were (or were not) called.
stub_noop() {
  local name="$1" rc="${2:-0}"
  cat >"$STUBDIR/$name" <<EOF
#!$HARNESS_BASH
printf '%s\n' "\$*" >>"\$STUBLOG/$name.log"
exit $rc
EOF
  chmod +x "$STUBDIR/$name"
}

# The whole point of logging: "how many times did nix build run" is the only way
# to test the efficiency claims, and "with what" is the only way to test that a
# trial tested the thing it said it did.
stub_log() { cat "$STUBLOG/$1.log" 2>/dev/null || true; }

stub_count() {
  local name="$1" pattern="${2:-}"
  if [[ ! -f "$STUBLOG/$name.log" ]]; then
    echo 0
  elif [[ -z "$pattern" ]]; then
    awk 'END { print NR }' "$STUBLOG/$name.log"
  else
    awk -v p="$pattern" 'index($0, p) { n++ } END { print n + 0 }' "$STUBLOG/$name.log"
  fi
}

# --- Running the scripts under test -------------------------------------------------
# PATH is assembled stubs-first. That is the whole reason the suite runs the raw
# fragment under a synthesized preamble instead of the built derivation:
# writeShellApplication *prepends* its runtimeInputs, so inside a real drtv-dl
# no amount of PATH manipulation can shadow the genuine yt-dlp.
test_path() { printf '%s:%s:%s' "$STUBDIR" "$REALBIN" "$PATH"; }

# For a case that calls extracted functions in its own shell rather than running
# a script: the functions still shell out to date, sleep, curl and unzip, so the
# case needs the same PATH a run of the script would get.
use_test_path() {
  PATH="$(test_path)"
  export PATH
}

# Set RUN_CWD to run the next script from somewhere else — `-d .` and `-d ./`
# only mean anything relative to a working directory.
RUN_CWD=""

_capture() {
  local out="$TMP/.stdout" err="$TMP/.stderr"
  STATUS=0
  if [[ -n "$RUN_CWD" ]]; then
    (cd "$RUN_CWD" && exec "$@") >"$out" 2>"$err" || STATUS=$?
  else
    "$@" >"$out" 2>"$err" || STATUS=$?
  fi
  STDOUT="$(cat "$out")"
  STDERR="$(cat "$err")"
}

# The two pkgs/ fragments have no shebang and no `set` line: run one with plain
# `bash file.sh` and errexit, nounset and pipefail all silently vanish, which is
# exactly the class of bug the suite is hunting. This reproduces the preamble
# writeShellApplication generates, byte for byte in the parts that matter.
wrap_fragment() {
  local script="$1" wrapped="$2"
  {
    printf '#!%s\n' "$HARNESS_BASH"
    printf 'set -o errexit\nset -o nounset\nset -o pipefail\n\n'
    printf 'export PATH="%s"\n\n' "$(test_path)"
    cat "$script"
  } >"$wrapped"
  chmod +x "$wrapped"
}

run_fragment() {
  local script="$1"
  shift
  local wrapped="$TMP/wrapped-${script##*/}"
  wrap_fragment "$script" "$wrapped"
  _capture "$HARNESS_BASH" "$wrapped" "$@"
}

# flake-up-safe.sh carries its own shebang and its own `set -euo pipefail`, so
# it is run as itself — from its real path, because it locates the flake it
# belongs to through $BASH_SOURCE.
run_flake_up_safe() {
  _capture env PATH="$(test_path)" "$HARNESS_BASH" "$FLAKE_UP_SAFE" "$@"
}

# --- Unit-testing individual functions ------------------------------------------------
# For the pure ones — quota arithmetic, path classification, the on-disk tests —
# an end-to-end run is a very expensive way to check a subtraction. Pull the
# function text out and source it with the globals it needs set explicitly. The
# extraction is deliberately strict: a function that has been renamed or
# reformatted makes the case error out rather than quietly testing nothing.
extract_funcs() {
  local file="$1" out="$2"
  shift 2
  local name found
  : >"$out"
  for name in "$@"; do
    found="$(awk -v fn="$name" '
      $0 == fn "() {" { inside = 1 }
      inside { print }
      inside && $0 == "}" { inside = 0; exit }
    ' "$file")"
    if [[ -z "$found" ]]; then
      fail "harness: could not extract function '$name' from ${file##*/}" \
        "it must be defined as '$name() {' at column 0 and end with '}' at column 0"
      exit 1
    fi
    printf '%s\n\n' "$found" >>"$out"
  done
}
