#!/usr/bin/env bash

set -euo pipefail

# Run the script in a nix-shell with the required packages
nix-shell -p bitwarden-cli jq sops git --run "$(cat <<'EOF'
set -euo pipefail

# Log in to Bitwarden
echo "Logging in to Bitwarden..."
bw login --check || bw login

# Sync the vault
echo "Syncing Bitwarden vault..."
bw sync

# Get the age key from the note
echo "Fetching age key from Bitwarden..."
AGE_KEY=$(bw get notes fw13-age-key | jq -r '.notes')

if [[ -z "$AGE_KEY" ]]; then
    echo "Could not find the age key in Bitwarden."
    echo "Please ensure a note named 'fw13-age-key' exists and contains your age key."
    exit 1
fi

# Create a temporary directory for the age key
AGE_KEY_DIR=$(mktemp -d)
echo "$AGE_KEY" > "$AGE_KEY_DIR/key.txt"

# Create the sops directory on the target system
SOPS_DIR="/mnt/home/emil/.config/sops/age"
mkdir -p "$SOPS_DIR"

# Save the key to the file on the target system
KEY_FILE="$SOPS_DIR/keys.txt"
echo "$AGE_KEY" > "$KEY_FILE"
chmod 600 "$KEY_FILE"

echo "Successfully saved age key to $KEY_FILE on the target system."

# Decrypt the luks key for disko
echo "Decrypting LUKS key for disko..."
sops --age-key-file "$AGE_KEY_DIR/key.txt" -d /tmp/nix-conf/secrets/luks.yaml | jq -r .luks_key > /tmp/secret.key
chmod 600 /tmp/secret.key

echo "Successfully decrypted LUKS key to /tmp/secret.key"

# Clean up temporary age key directory
rm -rf "$AGE_KEY_DIR"
EOF
)"
