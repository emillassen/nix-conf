#!/usr/bin/env bash

set -euo pipefail

# Check if Bitwarden CLI is installed
if ! command -v bw &> /dev/null; then
    echo "Bitwarden CLI (bw) is not installed. Please install it first."
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please install it first."
    exit 1
fi

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

# Create the sops directory if it doesn't exist
SOPS_DIR="$HOME/.config/sops/age"
mkdir -p "$SOPS_DIR"

# Save the key to the file
KEY_FILE="$SOPS_DIR/keys.txt"
echo "$AGE_KEY" > "$KEY_FILE"
chmod 600 "$KEY_FILE"

echo "Successfully saved age key to $KEY_FILE"
