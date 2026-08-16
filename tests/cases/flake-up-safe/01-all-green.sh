#!/usr/bin/env bash
# Property 1: everything builds at its tip → the whole set is taken in a single
# trial, every input ends at its tip, and flake.lock is written.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: all inputs green"

use_stubs nix git curl gh
sim_init
sim_input nixpkgs NixOS/nixpkgs nixos-unstable base-nixpkgs 1750000000 tip-nixpkgs 1755000000
sim_input disko nix-community/disko main base-disko 1750000000 tip-disko 1755000000
sim_input hm nix-community/home-manager master base-hm 1750000000 tip-hm 1755000000
sim_write
sim_verdict <<'EOF'
exit 0
EOF

run_flake_up_safe -f "$FLAKE"

assert_exit "exits 0" 0
assert_contains "reports the write" "$STDOUT" "Wrote flake.lock (verified)"
assert_eq "nixpkgs at tip" "tip-nixpkgs" "$(lock_rev nixpkgs)"
assert_eq "disko at tip" "tip-disko" "$(lock_rev disko)"
assert_eq "hm at tip" "tip-hm" "$(lock_rev hm)"

# Two builds and no more: the baseline, then the whole set at once. The final
# whole-combination verification is byte-identical to the set trial, so the .drv
# cache answers it for free — that is the point of splitting eval from build.
assert_eq "exactly two builds (baseline + all tips)" 2 "$(builds_run)"
assert_contains "final trial was free" "$STDOUT" "identical to t02"
