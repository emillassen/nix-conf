#!/usr/bin/env bash
# This script generates the SMB credentials file from sops secrets

cat > /etc/nixos/smb-secrets << EOF
username=$(cat /run/secrets/smb_username)
password=$(cat /run/secrets/smb_password)
domain=
EOF

chmod 600 /etc/nixos/smb-secrets
