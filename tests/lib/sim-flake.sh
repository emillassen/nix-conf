# shellcheck shell=bash
# Builds the universe flake-up-safe.sh searches: a flake directory with a
# flake.lock, a committed (HEAD) baseline lock, a tip for every input, and a
# truth table saying which combinations build.
#
# Used as:
#
#   sim_init
#   sim_input nixpkgs NixOS/nixpkgs nixos-unstable base1 1750000000 tip1 1755000000
#   sim_input disko   nix-community/disko main      base2 1750000000 tip2 1755000000
#   sim_write
#   sim_verdict <<'EOF'
#   grep -q 'disko=tip2' && exit 1 || exit 0
#   EOF
#
# The verdict script reads the combination (one `name=rev` line per input that
# reaches the target) on stdin and exits 0 when that lock builds.

SIM=""
FLAKE=""
SIM_INPUTS=()

sim_init() {
  SIM="$TMP/sim"
  FLAKE="$TMP/flake"
  mkdir -p "$SIM/drvs" "$FLAKE"
  SIM_INPUTS=()
  : >"$SIM/revs"
  : >"$SIM/tips"
  # find_flake_root only looks for the file; nothing ever evaluates it.
  echo '{ }' >"$FLAKE/flake.nix"
  export FLAKE_SIM="$SIM"
  export CURL_MAP="$SIM/curl-map"
  export GH_MAP="$SIM/gh-map"
  : >"$CURL_MAP"
  : >"$GH_MAP"
}

# name owner/repo ref baserev basets tiprev tipts [type]
sim_input() {
  local name="$1" slug="$2" ref="$3" brev="$4" bts="$5" trev="$6" tts="$7" type="${8:-github}"
  SIM_INPUTS+=("$name"$'\t'"$slug"$'\t'"$ref"$'\t'"$brev"$'\t'"$bts"$'\t'"$trev"$'\t'"$tts"$'\t'"$type")
  sim_rev "$brev" "$bts"
  sim_rev "$trev" "$tts"
  printf '%s\t%s\t%s\n' "$name" "$trev" "$tts" >>"$SIM/tips"
}

# Every revision the sim can be pinned to needs a timestamp, or "is this newer
# than the baseline" has nothing to compare.
sim_rev() {
  printf '%s\t%s\n' "$1" "$2" >>"$SIM/revs"
}

_sim_lock() {
  local which="$1"
  printf '%s\n' "${SIM_INPUTS[@]}" | jq -Rn --arg which "$which" '
    [inputs | select(length > 0) | split("\t")
     | {name: .[0], owner: (.[1] | split("/")[0]), repo: (.[1] | split("/")[1]),
        ref: .[2], baserev: .[3], basets: .[4], tiprev: .[5], tipts: .[6], type: .[7]}]
    | map(. + {rev: (if $which == "base" then .baserev else .tiprev end),
               ts: (if $which == "base" then .basets else .tipts end)})
    | . as $in
    | {
        nodes: (
          {root: {inputs: ([$in[] | {key: .name, value: .name}] | from_entries)}}
          + ([$in[] | {key: .name, value: {
               locked: ({lastModified: (.ts | tonumber),
                         narHash: ("sha256-" + .rev[0:16]),
                         rev: .rev, type: .type}
                        + (if .type == "github" then {owner: .owner, repo: .repo} else {} end)),
               original: ({type: .type, ref: .ref}
                          + (if .type == "github" then {owner: .owner, repo: .repo} else {} end))
             }}] | from_entries)
        ),
        root: "root",
        version: 7
      }'
}

# Writes the committed baseline and makes the working tree match it, which is
# the ordinary starting state: a clean checkout whose lock is the one in HEAD.
sim_write() {
  _sim_lock base >"$SIM/head.lock"
  cp "$SIM/head.lock" "$FLAKE/flake.lock"
}

sim_verdict() {
  cat >"$SIM/verdict.sh"
  chmod +x "$SIM/verdict.sh"
}

sim_check() {
  cat >"$SIM/check.sh"
  chmod +x "$SIM/check.sh"
}

sim_reaching() {
  printf '%s\n' "$@" >"$SIM/reaching"
}

# A 40-hex revision that is readable in the output: `idxrev 7` is 0000007
# followed by thirty-three zeros, so both the seven-character short rev a
# channel release name carries and the ten characters flake-up-safe.sh prints
# per probe identify the candidate index. That is what makes the walk's visiting
# order assertable without reverse-engineering dates.
idxrev() { printf '%07d%033d' "$1" 0; }

# The candidate indices a bisect actually probed, in order, read back out of the
# run's own output. Only the probe lines carry a bare revision at the end; the
# "newest working candidate" summary line is prefixed with an arrow.
probed_indices() {
  grep -E '^    [^ →]' <<<"$1" | grep -oE '\b[0-9]{7}000\b' |
    cut -c1-7 | sed 's/^0*//; s/^$/0/' | tr '\n' ' ' | sed 's/ $//'
}

# A plausible-looking revision for cases that do not care which one it is.
hexrev() { printf '%s' "$1" | sha1sum | cut -d' ' -f1; }

# --- Candidate sources the bisect draws on -------------------------------------
# A day's worth of history for a non-channel input: `gh api repos/…/commits?…`
# answering with one commit for that day, and the revision registered so the
# "is it newer than the baseline" test at the end has a timestamp to read.
sim_gh_day() {
  local slug="$1" day="$2" rev="$3" ts="${4:-}"
  [[ -n "$ts" ]] || ts="$(date -u -d "${day}T12:00:00Z" +%s)"
  printf 'repos/%s/commits?sha=*until=%s*\t[{"sha":"%s"}]\n' "$slug" "$day" "$rev" >>"$GH_MAP"
  sim_rev "$rev" "$ts"
}

# GitHub answering nothing at all — rate-limited, offline, or a repo that moved.
sim_gh_dead() {
  printf 'repos/%s/commits?*\t-\n' "$1" >>"$GH_MAP"
}

# A channel's release list as the nix-releases bucket actually serves it, from
# lines of "serial<TAB>fullrev<TAB>lastModified" on stdin. The directory names
# carry a short rev and a serial, and the full revision comes from each
# release's own git-revision file — two different requests, both faked here.
#
# The keys go to the stub unsorted; it serves them lexicographically, as S3
# does, because sorting them back into chronological order is one of the things
# under test.
sim_channel_releases() {
  local prefix="$1" version="${2:-26.05}" sep="${3:-pre}"
  local serial rev ts name xml="$SIM/s3-${prefix//\//_}.keys"
  local -a names=()
  while IFS=$'\t' read -r serial rev ts; do
    [[ -n "$serial" ]] || continue
    name="nixos-${version}${sep}${serial}.${rev:0:7}"
    names+=("$name")
    printf 'https://releases.nixos.org/%s%s/git-revision\t200\t%s\n' \
      "$prefix" "$name" "$rev" >>"$CURL_MAP"
    sim_rev "$rev" "$ts"
  done
  : >"$xml"
  for name in "${names[@]}"; do printf '%s%s/\n' "$prefix" "$name" >>"$xml"; done
  # The curl stub answers this the way S3 does, marker and all.
  printf 'https://nix-releases.s3.amazonaws.com/?prefix=%s*\t200\t!s3 %s\n' \
    "$prefix" "$xml" >>"$CURL_MAP"
}

# Pads a channel's listing with COUNT more releases, keys only — no git-revision
# entry and no timestamp, because a candidate is resolved only when it is
# actually probed and these sit past the baseline the walk stops at. Their names
# carry an older version than the real releases', so they sort ahead of them and
# the tip ends up beyond the first page the bucket will serve. That is not a
# contrivance: a page holds 1000 keys, nixos/unstable/ holds a decade of them,
# and a channel publishing several a day fills a year's marker window.
sim_channel_filler() {
  local prefix="$1" count="$2" version="${3:-25.05}"
  local xml="$SIM/s3-${prefix//\//_}.keys" i
  for ((i = 1; i <= count; i++)); do
    printf '%snixos-%spre%06d.0000001/\n' "$prefix" "$version" "$i" >>"$xml"
  done
}

# --- Reading results back --------------------------------------------------------
lock_rev() {
  jq -r --arg n "$1" '
    . as $l | $l.nodes.root.inputs[$n] as $v
    | (if ($v | type) == "string" then $v else $v[-1] end) as $node
    | $l.nodes[$node].locked.rev // ""
  ' "${2:-$FLAKE/flake.lock}"
}

lock_ts() {
  jq -r --arg n "$1" '
    . as $l | $l.nodes.root.inputs[$n] as $v
    | (if ($v | type) == "string" then $v else $v[-1] end) as $node
    | $l.nodes[$node].locked.lastModified // 0
  ' "${2:-$FLAKE/flake.lock}"
}

# How many real builds the run cost. Trials answered from the .drv cache never
# reach `nix build`, which is exactly what the efficiency claims are about.
builds_run() { awk 'BEGIN { n = 0 } /^$/ { n++ } END { print n }' "$STUBLOG/builds.log" 2>/dev/null || echo 0; }

# The combination each build actually tested, one per line, as a compact
# "name=rev,name=rev" so a case can assert on the sequence.
build_combos() {
  awk 'BEGIN { RS = ""; FS = "\n" }
       { line = ""; for (i = 1; i <= NF; i++) line = line (i > 1 ? "," : "") $i; print line }' \
    "$STUBLOG/builds.log" 2>/dev/null || true
}
