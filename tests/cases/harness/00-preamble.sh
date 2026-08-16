#!/usr/bin/env bash
# A test of the suite itself. The two pkgs/ fragments have no shebang and no
# `set` line of their own — writeShellApplication supplies both — so running one
# with plain `bash file.sh` silently drops errexit, nounset and pipefail, which
# is exactly the class of bug the rest of the suite is hunting. If that ever
# stops being true, or the harness stops reproducing it, every green case below
# would be worth less than it looks.
. "${TESTS_DIR:?}/lib/harness.sh"
test_init "harness: the synthesized preamble"

for f in "$SEDL" "$DRTVDL"; do
  name="${f##*/}"
  assert_ne "$name has no shebang" '#!' "$(head -c2 "$f")"
  assert_eq "$name sets no shell options of its own" 0 \
    "$(grep -c '^set -' "$f" || true)"
done

# flake-up-safe.sh is the other way round: it is a script in its own right and
# is run as one.
assert_eq "flake-up-safe.sh has a shebang" '#!' "$(head -c2 "$FLAKE_UP_SAFE")"
assert_contains "and sets its own options" "$(head -n 60 "$FLAKE_UP_SAFE")" "set -euo pipefail"

# What the harness wraps a fragment in.
wrap_fragment "$SEDL" "$TMP/wrapped.sh"
assert_eq "the wrapper reproduces writeShellApplication's preamble" \
  "set -o errexit
set -o nounset
set -o pipefail" \
  "$(sed -n '2,4p' "$TMP/wrapped.sh")"
assert_eq "under a real bash" '#!' "$(head -c2 "$TMP/wrapped.sh")"
assert_contains "with the stub directory first on PATH" \
  "$(sed -n '6p' "$TMP/wrapped.sh")" "export PATH=\"$STUBDIR:"

# And the options really are in force in a wrapped run: an unset variable must
# be fatal.
printf 'echo "start"\necho "$definitely_not_set"\necho "end"\n' >"$TMP/frag.sh"
run_fragment "$TMP/frag.sh"
assert_ne "nounset is live inside a wrapped fragment" 0 "$STATUS"
assert_contains "and says which variable" "$STDERR" "definitely_not_set: unbound variable"
assert_not_contains "so the script stopped there" "$STDOUT" "end"
