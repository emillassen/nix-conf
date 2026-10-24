#!/usr/bin/env bash
#
# Provision the two secrets a fresh install needs, from the Bitwarden note
# fw13-age-key. Two phases, because they straddle disko:
#
#   fetch    Before disko. Stages the age key at /tmp/fw13-age-key.txt and uses
#            it to decrypt secrets/luks.yaml to /tmp/secret.key, the
#            passwordFile nixos/disks.nix hands to cryptsetup.
#   install  After disko has mounted the target at /mnt, before nixos-install.
#            Copies the staged key to /mnt/home/emil/.config/sops/age/keys.txt
#            and deletes both staged files.
#
# The key cannot be written in the fetch phase: /mnt is not mounted yet, so it
# would land on the installer's own filesystem and disappear under the target's
# mount. And it has to be there before nixos-install, not after: the activation
# nixos-install runs already decrypts emil_password_hash (neededForUsers), and
# generateKey = false leaves no fallback.
set -euo pipefail

STAGE=/tmp/fw13-age-key.txt
LUKS_KEY=/tmp/secret.key
TARGET=/mnt
# Pinned in nixos/configuration.nix (users.users.emil.uid); `users` is NixOS's
# fixed gid 100. Numeric, because the installer's /etc/passwd has no emil.
EMIL_UID=1000
EMIL_GID=100

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  echo "Usage: $0 fetch|install" >&2
  exit 2
}

fetch() {
  # The installer ISO has none of these; the installed system has all three.
  if ! command -v bw >/dev/null || ! command -v sops >/dev/null || ! command -v age-keygen >/dev/null; then
    exec nix-shell -p bitwarden-cli sops age --run "$(printf '%q ' "${BASH_SOURCE[0]}" fetch)"
  fi

  umask 077
  local tmp_age tmp_luks
  tmp_age="$(mktemp /tmp/fw13-age-key.XXXXXX)"
  tmp_luks="$(mktemp /tmp/secret.key.XXXXXX)"
  # shellcheck disable=SC2064 # expand now: the names are local
  trap "rm -f '$tmp_age' '$tmp_luks'" EXIT

  # `bw login` alone leaves the vault locked, and so does a login left over from
  # an earlier attempt; every read needs a session key. --raw prints only that
  # key (the prompts go to stderr).
  if [[ -n "${BW_SESSION:-}" ]] && bw unlock --check >/dev/null 2>&1; then
    :
  elif bw login --check >/dev/null 2>&1; then
    echo "Unlocking Bitwarden..."
    BW_SESSION="$(bw unlock --raw)"
  else
    echo "Logging in to Bitwarden..."
    BW_SESSION="$(bw login --raw)"
  fi
  export BW_SESSION
  [[ -n "$BW_SESSION" ]] || {
    echo "No Bitwarden session." >&2
    exit 1
  }
  bw sync >/dev/null

  echo "Fetching the age key from Bitwarden..."
  # `get notes` prints the note's text as it is; there is no JSON to parse.
  local note
  note="$(bw get notes fw13-age-key)"
  printf '%s\n' "$note" >"$tmp_age"

  # A note that is not an age key, or is a different one, must stop here rather
  # than surface as an undecryptable system after the disk has been wiped.
  local pub
  if ! pub="$(age-keygen -y "$tmp_age" 2>/dev/null)" || [[ -z "$pub" ]]; then
    echo "The note fw13-age-key does not hold an age secret key." >&2
    exit 1
  fi
  if ! grep -qF "$pub" "$repo/.sops.yaml"; then
    echo "The age key in fw13-age-key ($pub) is not a recipient in .sops.yaml." >&2
    exit 1
  fi

  echo "Decrypting the LUKS key for disko..."
  # --extract prints the bare value, without a trailing newline, and fails on a
  # missing key instead of printing "null".
  SOPS_AGE_KEY_FILE="$tmp_age" sops decrypt --extract '["luks_key"]' "$repo/secrets/luks.yaml" >"$tmp_luks"
  if [[ ! -s "$tmp_luks" ]]; then
    echo "secrets/luks.yaml decrypted to an empty luks_key." >&2
    exit 1
  fi

  mv -f "$tmp_age" "$STAGE"
  mv -f "$tmp_luks" "$LUKS_KEY"
  trap - EXIT
  echo "Staged the age key at $STAGE and the LUKS key at $LUKS_KEY."
  echo "Next: run disko, then: sudo $0 install"
}

install_key() {
  if [[ $EUID -ne 0 ]]; then
    exec sudo "${BASH_SOURCE[0]}" install
  fi
  if [[ ! -s "$STAGE" ]]; then
    echo "No staged age key at $STAGE; run '$0 fetch' first." >&2
    exit 1
  fi
  # Before disko, $TARGET is the installer's own directory and the key would be
  # hidden by the mount that follows.
  if ! mountpoint -q "$TARGET"; then
    echo "$TARGET is not mounted; run disko first." >&2
    exit 1
  fi

  local home="$TARGET/home/emil"
  # Owned by emil from the start: Home Manager writes into ~/.config as emil, and
  # `sops secrets/*.yaml` reads this key as emil. Root (sops-nix) reads it anyway.
  install -d -m 0700 -o "$EMIL_UID" -g "$EMIL_GID" "$home"
  install -d -m 0755 -o "$EMIL_UID" -g "$EMIL_GID" "$home/.config"
  install -d -m 0700 -o "$EMIL_UID" -g "$EMIL_GID" "$home/.config/sops" "$home/.config/sops/age"
  install -m 0600 -o "$EMIL_UID" -g "$EMIL_GID" "$STAGE" "$home/.config/sops/age/keys.txt"
  echo "Installed the age key at $home/.config/sops/age/keys.txt."

  # disko has consumed the LUKS key; it is not needed at boot (the initrd asks
  # for the passphrase), so neither staged file has any further use.
  rm -f "$STAGE" "$LUKS_KEY"
  echo "Removed $STAGE and $LUKS_KEY. Next: nixos-install."
}

[[ $# -eq 1 ]] || usage
case "$1" in
fetch) fetch ;;
install) install_key ;;
*) usage ;;
esac
