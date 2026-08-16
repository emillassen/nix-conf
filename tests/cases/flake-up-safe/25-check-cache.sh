#!/usr/bin/env bash
# `nix flake check` is keyed on the lock file rather than on the .drv, because it
# covers outputs the target's derivation says nothing about. That makes it the
# one verdict the .drv cache cannot answer — so it needs a cache of its own, and
# case 21 only ever exercises it for pass and fail, never for reuse.
#
# Reuse is not a nicety here: `nix flake check` evaluates the whole system, and a
# run that repeated it once per trial would roughly double a multi-hour search.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: the flake check verdict is cached per lock"

use_stubs nix git curl gh
sim_init
sim_input a org/a main base-a 1750000000 tip-a 1755000000
sim_input b org/b main base-b 1750000000 tip-b 1755000000
sim_write
cp "$FLAKE/flake.lock" "$TMP/before.lock"
sim_verdict <<'EOF'
exit 0
EOF
sim_check <<'EOF'
exit 0
EOF

run_flake_up_safe -f "$FLAKE" -k
assert_exit "exits 0" 0
assert_eq "both inputs reached their tips" "tip-a tip-b" "$(lock_rev a) $(lock_rev b)"
# Three trials run: baseline, all-tips, and the final verification. The final
# composition is byte-identical to the all-tips lock, so it is the same key and
# the check is not paid for twice.
assert_eq "three trials" 3 "$(stub_count nix 'path-info')"
assert_eq "but only two distinct locks were checked" 2 "$(stub_count nix 'flake check')"

# The negative half. b's tip builds but fails the check, so the all-tips lock is
# remembered as bad — and the trial that follows ("keep a, add b") composes that
# very same lock again. It has to be rejected on the cached verdict rather than
# re-running the check, or every partition step would pay for one.
rm -f "$STUBLOG/nix.log" "$STUBLOG/builds.log"
cp "$TMP/before.lock" "$FLAKE/flake.lock"
sim_check <<'EOF'
grep -qx 'b=tip-b' && exit 1
exit 0
EOF

run_flake_up_safe -f "$FLAKE" -k --no-bisect
assert_exit "exits 0" 0
assert_eq "a reached its tip" "tip-a" "$(lock_rev a)"
assert_eq "b was held back on the check's word" "base-b" "$(lock_rev b)"
# baseline, all-tips (fails the check), {a} alone. The {b} trial reuses the
# all-tips lock and is answered from both caches — the .drv one says it builds,
# the lock one says it does not check out — so it costs neither a build nor a
# check.
assert_eq "the repeated lock cost no second check" 3 "$(stub_count nix 'flake check')"
assert_eq "and no second build either" 3 "$(builds_run)"
assert_contains "the build half was recognised as a repeat" "$STDOUT" "builds (identical to"
