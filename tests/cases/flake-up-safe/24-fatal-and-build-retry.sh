#!/usr/bin/env bash
# Two things a failed build can mean besides "this combination is broken", and
# the run has to tell all three apart. A full disk or a dead daemon is a fact
# about the machine — every trial after it inherits the same fate, so continuing
# would record a wall of false verdicts against innocent inputs. A dropped packet
# is worth exactly one retry. Anything else is the inputs' fault.
#
# The update-level retry has a case of its own (18); this is the build-level one,
# plus both call sites of abort_if_fatal — the build and the evaluation.
. "${TESTS_DIR:?}/lib/harness.sh"
. "$TESTS_DIR/lib/sim-flake.sh"
test_init "flake-up-safe: fatal build environment vs. a transient blip"

use_stubs nix git curl gh
sim_init
sim_input a org/a main base-a 1750000000 tip-a 1755000000
sim_input b org/b main base-b 1750000000 tip-b 1755000000
sim_write
cp "$FLAKE/flake.lock" "$TMP/before.lock"

# --- the disk fills up part-way through -------------------------------------
# The baseline builds; the first trial that moves anything forward dies of a
# full disk. Nothing can be concluded from that, so the run must stop there
# rather than partition its way through every input recording failures.
sim_verdict <<'EOF'
combo="$(cat)"
case "$combo" in
  *=tip-*)
    echo "error: writing to '/nix/store/x.drv': No space left on device" >&2
    exit 1
    ;;
esac
exit 0
EOF

run_flake_up_safe -f "$FLAKE"
assert_exit "the run stops" 1
assert_contains "and blames the machine, not the inputs" "$STDERR" \
  "the build environment failed, not the inputs — nothing can be concluded"
assert_files_identical "flake.lock left exactly as found" "$TMP/before.lock" "$FLAKE/flake.lock"
# Baseline, then the all-tips trial that hit the wall. Partitioning would have
# cost two more, and each would have been a lie about an input.
assert_eq "it did not carry on partitioning" 2 "$(builds_run)"

# The evaluation call site is the other half: a daemon that has gone away shows
# up before any build starts.
rm -f "$STUBLOG/builds.log"
cp "$TMP/before.lock" "$FLAKE/flake.lock"
cat >"$SIM/eval.sh" <<'EOF'
#!/usr/bin/env bash
combo="$(cat)"
case "$combo" in
  *=tip-*)
    echo "error: cannot connect to daemon at '/nix/var/nix/daemon-socket/socket'" >&2
    exit 1
    ;;
esac
exit 0
EOF
chmod +x "$SIM/eval.sh"
run_flake_up_safe -f "$FLAKE"
assert_exit "a dead daemon stops the run too" 1
assert_contains "with the same verdict" "$STDERR" "the build environment failed"
assert_files_identical "and the lock still untouched" "$TMP/before.lock" "$FLAKE/flake.lock"
rm -f "$SIM/eval.sh"

# --- a dropped packet is worth one retry -------------------------------------
rm -f "$STUBLOG/builds.log"
cp "$TMP/before.lock" "$FLAKE/flake.lock"
sim_verdict <<'EOF'
combo="$(cat)"
case "$combo" in
  *b=tip-b*)
    n=0
    [ -f "$FLAKE_SIM/blips" ] && n="$(cat "$FLAKE_SIM/blips")"
    n=$((n + 1))
    printf '%s' "$n" >"$FLAKE_SIM/blips"
    if [ "$n" -le "$(cat "$FLAKE_SIM/blip-budget")" ]; then
      echo "error: unable to download 'https://cache.nixos.org/nar/x': Couldn't resolve host name" >&2
      exit 1
    fi
    ;;
esac
exit 0
EOF
printf '1' >"$SIM/blip-budget"

run_flake_up_safe -f "$FLAKE"
assert_exit "one blip does not sink the run" 0
assert_contains "and it says it retried" "$STDOUT" "network trouble, retrying once"
assert_eq "a reached its tip" "tip-a" "$(lock_rev a)"
assert_eq "b reached its tip on the retry" "tip-b" "$(lock_rev b)"
# Baseline, the blip, the retry that worked. The final verification is answered
# from the .drv cache, so it costs nothing.
assert_eq "the retry cost exactly one extra build" 3 "$(builds_run)"

# --- a failure that outlasts the retry is a verdict on the input --------------
# Two attempts and no more: without the `attempt -eq 1` guard this is an
# infinite loop, and with no retry at all b would be held back for a blip.
rm -f "$STUBLOG/builds.log" "$SIM/blips"
cp "$TMP/before.lock" "$FLAKE/flake.lock"
printf '99' >"$SIM/blip-budget"

run_flake_up_safe -f "$FLAKE" --no-bisect
assert_exit "the run finishes" 0
assert_eq "a still reached its tip" "tip-a" "$(lock_rev a)"
assert_eq "b is held back" "base-b" "$(lock_rev b)"
assert_contains "and reported as held back" "$STDOUT" "held back  b"
# baseline, then {a,b} twice — the blip and its one retry — then {a} alone. The
# {b} trial that follows is "keep a, add b", which is the same combination the
# {a,b} trial already tested, so the .drv cache answers it without building and
# the retry is not paid a second time. Two attempts and no more is also what
# stops the `attempt -eq 1` guard from being an infinite loop.
assert_eq "one retry per distinct combination, not per trial" 4 "$(builds_run)"
assert_contains "the repeat is recognised as one" "$STDOUT" "failed (identical to"
