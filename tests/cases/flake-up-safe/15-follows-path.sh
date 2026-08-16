#!/usr/bin/env bash
# A top-level `inputs.x.follows = "y/z"` makes root.inputs.x an array — a path
# to walk from root ("root's input y, then that node's input z"), not a node
# name. Taking its last element is only right by luck: here `z` is the input
# name `nixpkgs`, which is also a node key, but the node it names is the wrong
# one. This repo's own lock has llm-agents holding a *separate* nixpkgs node, so
# a single `follows` line would be enough to hit it.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: a follows path in root.inputs"

use_stubs nix git curl gh
sim_init

ROOT_NIXPKGS_TS=1767225600      # 2026-01-01
AGENTS_NIXPKGS_TS=1750000000    # 2025-06-15
AGENTS_TS=1767225600

cat >"$SIM/head.lock" <<EOF
{
  "nodes": {
    "root": {
      "inputs": {
        "agents": "llm-agents",
        "agents-pkgs": ["agents", "nixpkgs"],
        "nixpkgs": "nixpkgs"
      }
    },
    "nixpkgs": {
      "locked": {"lastModified": $ROOT_NIXPKGS_TS, "narHash": "sha256-a",
                 "owner": "NixOS", "repo": "nixpkgs", "rev": "$(hexrev root-nixpkgs)",
                 "type": "github"},
      "original": {"owner": "NixOS", "repo": "nixpkgs", "ref": "nixos-unstable", "type": "github"}
    },
    "nixpkgs_2": {
      "locked": {"lastModified": $AGENTS_NIXPKGS_TS, "narHash": "sha256-b",
                 "owner": "NixOS", "repo": "nixpkgs", "rev": "$(hexrev agents-nixpkgs)",
                 "type": "github"},
      "original": {"owner": "NixOS", "repo": "nixpkgs", "ref": "nixos-unstable", "type": "github"}
    },
    "llm-agents": {
      "inputs": {"nixpkgs": "nixpkgs_2"},
      "locked": {"lastModified": $AGENTS_TS, "narHash": "sha256-c",
                 "owner": "numtide", "repo": "llm-agents", "rev": "$(hexrev agents)",
                 "type": "github"},
      "original": {"owner": "numtide", "repo": "llm-agents", "ref": "main", "type": "github"}
    }
  },
  "root": "root",
  "version": 7
}
EOF
cp "$SIM/head.lock" "$FLAKE/flake.lock"

# Only the two real inputs have tips; the follows entry is not something
# `nix flake update` can move on its own.
{
  printf 'nixpkgs\t%s\t%s\n' "$(hexrev root-nixpkgs-tip)" "$((ROOT_NIXPKGS_TS + 5 * 86400))"
  printf 'agents\t%s\t%s\n' "$(hexrev agents-tip)" "$((AGENTS_TS + 5 * 86400))"
} >"$SIM/tips"
sim_verdict <<'EOF'
exit 0
EOF

run_flake_up_safe -f "$FLAKE" -n

assert_exit "exits 0" 0
# The follows entry resolves to nixpkgs_2, which nothing moved, so it is
# unchanged and dated 2025-06-15. Reading it as the root nixpkgs node instead
# would date it 2026-01-01 and claim an update is available for it.
assert_matches "the follows path resolves to the node it actually points at" \
  "$STDOUT" '= agents-pkgs +unchanged \(2025-06-15\)'
assert_not_contains "and is not mistaken for the root nixpkgs" "$STDOUT" \
  "↻ agents-pkgs"
