#!/usr/bin/env bash

set -euo pipefail

# Check if Bitwarden CLI is installed
if ! command -v bw &> /dev/null; then
    echo "Bitwarden CLI (bw) is not installed. Please install it first."
    exit 1
fi

# Log in to Bitwarden
echo "Logging in to Bitwarden..."
bw login --check || bw login

# Sync the vault
echo "Syncing Bitwarden vault..."
bw sync

# Get the public key from the attachment
echo "Fetching public key from Bitwarden..."
ITEM_ID=$(bw list items --search gpg | jq -r '.[0].id')
bw get attachment pub.asc --itemid "$ITEM_ID" --output ./pub.asc

# Import the GPG key
echo "Importing GPG key..."
gpg --keyid-format 0xlong --import ./pub.asc

# Get the key ID
echo "Getting key ID..."
KEY_ID=$(gpg --keyid-format 0xlong --card-status | grep 'sec#' | awk '{print $2}' | cut -d'/' -f2)

# Set up SSH key
echo "Setting up SSH key..."
ssh-add -L | awk -v keyid="$KEY_ID" '$0 ~ keyid {print $1 " " $2 " emil@emillassen.com"}' | tee ~/.ssh/emillassen.pub
chmod 0600 ~/.ssh/emillassen.pub

# Clean up
rm ./pub.asc

echo "YubiKey setup complete."
