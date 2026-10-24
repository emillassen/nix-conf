#!/usr/bin/env bash
#
# Import the public half of the YubiKey's GPG key from Bitwarden (the pub.asc
# attachment on the vault item that carries it) and write its authentication
# subkey out as ~/.ssh/emillassen.pub.
set -euo pipefail

for tool in bw jq gpg; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not installed. Please install it first." >&2
    exit 1
  fi
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# `bw login` alone leaves the vault locked, and so does a login left over from
# an earlier run; every read needs a session key. --raw prints only that key.
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
echo "Syncing Bitwarden vault..."
bw sync >/dev/null

# The item that has a pub.asc attached, and exactly one of them. Taking the first
# hit of a search for "gpg" imported whichever item happened to sort first.
echo "Fetching public key from Bitwarden..."
ITEM_ID="$(bw list items --search gpg |
  jq -r '[.[] | select(any(.attachments[]?; .fileName == "pub.asc"))]
         | if length == 1 then .[0].id else "\(length)" end')"
if [[ ! "$ITEM_ID" =~ [a-f] ]]; then
  echo "Expected one Bitwarden item with a pub.asc attachment, found $ITEM_ID." >&2
  exit 1
fi
bw get attachment pub.asc --itemid "$ITEM_ID" --output "$work/pub.asc" >/dev/null

# The fingerprint comes from the key just fetched, not from whatever a grep of
# `gpg --card-status` turns up (which needed `sec#` and so missed a card whose
# primary key shows as `sec>`).
FPR="$(gpg --with-colons --import-options show-only --import "$work/pub.asc" 2>/dev/null |
  awk -F: '$1 == "fpr" { print $10; exit }')"
if [[ -z "$FPR" ]]; then
  echo "pub.asc holds no OpenPGP key." >&2
  exit 1
fi

echo "Importing GPG key $FPR..."
gpg --keyid-format 0xlong --import "$work/pub.asc"

# gpg exports the key's authentication subkey in SSH form itself; no agent and
# no match on a comment involved. The old filter over `ssh-add -L` matched
# nothing when the agent's comment was a `cardno:`, and `tee` then emptied the
# existing public key file.
echo "Setting up SSH key..."
ssh_key="$(gpg --export-ssh-key "$FPR" | awk '{ print $1 " " $2 " emil@emillassen.com" }')" ||
  ssh_key=""
if [[ ! "$ssh_key" =~ ^(ssh-|ecdsa-)[^\ ]+\ [A-Za-z0-9+/=]+\  ]]; then
  echo "Key $FPR has no authentication subkey to export for SSH; ~/.ssh left as it was." >&2
  exit 1
fi
install -d -m 0700 ~/.ssh
printf '%s\n' "$ssh_key" >"$work/emillassen.pub"
install -m 0600 "$work/emillassen.pub" ~/.ssh/emillassen.pub
cat ~/.ssh/emillassen.pub

echo "YubiKey setup complete."
