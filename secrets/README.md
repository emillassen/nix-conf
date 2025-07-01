# sops-nix Setup

This directory contains encrypted secrets managed by sops-nix.

## Files

- `secrets.yaml` - Encrypted secrets file
- `.sops.yaml` - sops configuration
- `keys/users/emil.txt` - Your age private key (gitignored)

## Usage

### Editing secrets

To edit the encrypted secrets file:

```bash
cd secrets
nix shell nixpkgs#sops -c sops secrets.yaml
```

### Adding new secrets

1. Edit the secrets.yaml file using the command above
2. Add the new secret key to the sops configuration in `/nixos/configuration.nix`
3. Rebuild the system

### Current secrets

- `smb_username` - SMB/CIFS username for NAS access
- `smb_password` - SMB/CIFS password for NAS access

## Important Notes

- The age private key is automatically generated and stored in `/home/emil/.config/sops/age/keys.txt`
- Private keys are protected by .gitignore
- Only encrypted secrets are committed to git
- Secrets are automatically decrypted at boot time by sops-nix
