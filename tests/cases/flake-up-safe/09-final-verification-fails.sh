#!/usr/bin/env bash
# Property 9: when the state that each step accepted turns out not to hold up as
# a whole, the run says so and falls back to the baseline rather than writing
# it.
#
# Getting there takes an *evaluation* failure, not a build failure: the final
# composition is byte-identical to the last state a step already verified, so
# the .drv cache answers its build without running one. See the report — the
# build-failure half of this branch is unreachable in practice.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: the final whole-combination check fails"

use_stubs nix git curl gh
sim_init
T=1767225600
sim_input a org/a main base-a "$T" tip-a "$((T + 10 * 86400))"
sim_input b org/b main base-b "$T" "$(idxrev 0)" "$((T + 10 * 86400))"
sim_write
cp "$FLAKE/flake.lock" "$TMP/before.lock"
sim_gh_day org/b "$(date -u -d "@$((T + 9 * 86400))" +%F)" "$(idxrev 1)" "$((T + 9 * 86400))"
sim_gh_day org/b "$(date -u -d "@$((T + 8 * 86400))" +%F)" "$(idxrev 2)" "$((T + 8 * 86400))"

sim_verdict <<EOF
grep -qx 'b=$(idxrev 0)' && exit 1
exit 0
EOF

# The seventh evaluation is the final whole-combination one; make nix fall over
# there the way an out-of-memory or a transient eval error would.
cat >"$SIM/eval.sh" <<'EOF'
#!/usr/bin/env bash
n="$FLAKE_SIM/eval-count"
c=0; [ -f "$n" ] && c=$(cat "$n")
echo $((c + 1)) >"$n"
[ "$c" -ge 6 ] && exit 1
exit 0
EOF
chmod +x "$SIM/eval.sh"

run_flake_up_safe -f "$FLAKE" -d 3

assert_exit "exits 0" 0
assert_contains "says the combination does not hold" "$STDERR" \
  "The combination that each step accepted does not build together."
assert_contains "says what it falls back to" "$STDERR" "Falling back to the head baseline."
assert_files_identical "the baseline is what gets left behind" \
  "$TMP/before.lock" "$FLAKE/flake.lock"
assert_contains "reports nothing as improved" "$STDOUT" "Nothing improved on the baseline"
