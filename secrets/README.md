# Secrets Management with sops-nix

This directory contains encrypted secrets managed by [sops](https://github.com/mozilla/sops) and integrated with NixOS via [sops-nix](https://github.com/Mic92/sops-nix).

## Directory Structure

```
├── .sops.yaml          # sops configuration with creation rules
secrets/
├── smb.yaml            # SMB/CIFS credentials
├── system.yaml         # System secrets (emil's password hash)
├── luks.yaml           # LUKS disk encryption key
└── README.md           # This file
```

## Initial Setup

### 1. Age Key Setup

`sops.age.generateKey = false` in `nixos/common/sops.nix` — the age key is **not** generated on first boot. It must be provisioned before the system can decrypt anything (in particular `emil_password_hash`, which is `neededForUsers = true` and required during a fresh install).

For a fresh install, `scripts/pre-install-secrets.sh` fetches the key from Bitwarden (a secure note named `fw13-age-key`) and:

- writes it to `/mnt/home/emil/.config/sops/age/keys.txt` on the target system, and
- uses it to decrypt `secrets/luks.yaml` to `/tmp/secret.key` for disko to consume during partitioning.

```bash
./scripts/pre-install-secrets.sh
```

If you need to manage the key manually instead:

```bash
# Generate new key (only if needed, e.g. bootstrapping a brand new key)
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt

# View your public key (to share with others, or to add as a recipient in .sops.yaml)
age-keygen -y ~/.config/sops/age/keys.txt
```

### 2. Set Up Secrets

1. **Edit a secrets file (creates it if it doesn't exist):**

   ```bash
   sops secrets/smb.yaml
   sops secrets/system.yaml
   sops secrets/luks.yaml
   ```

   sops uses the creation rules in `.sops.yaml` to encrypt the file for the `emil` age recipient.

## Daily Usage

### Direct sops Commands

```bash
cd secrets

# Edit secrets (decrypts to a temp file, re-encrypts on save)
sops smb.yaml
sops system.yaml
sops luks.yaml

# View decrypted secrets
sops -d smb.yaml
```

### Adding New Secret Files

1. **Create the new secret file:**

   ```bash
   echo "new_secret: your_value_here" > secrets/new-service.yaml
   ```

2. **Add creation rule to `.sops.yaml`:**

   ```yaml
   - path_regex: new-service\.yaml$
     key_groups:
       - age:
           - *emil
   ```

3. **Encrypt the file:**

   ```bash
   sops -e -i secrets/new-service.yaml
   ```

4. **Add to sops configuration (`nixos/common/sops.nix`):**

   ```nix
   sops.secrets.new_secret = {
     sopsFile = ../../secrets/new-service.yaml;
     owner = config.users.users.emil.name;
     group = config.users.groups.users.name;
     mode = "0400";
   };
   ```

## How sops-nix Integration Works

### Secret Mounting

- Encrypted files are decrypted at boot and mounted to `/run/secrets/`
- Example: `smb_username` secret → `/run/secrets/smb_username`

### Template System

- Use `config.sops.placeholder.secret_name` in templates
- Templates are rendered to `/run/secrets-rendered/`
- Example: SMB credentials template → `/run/secrets-rendered/smb-credentials`

### Configuration Files

**nixos/common/sops.nix**: Defines which secrets to decrypt, where to place them, and runs `sops-secrets-validation` to check that secrets are readable after boot
**nixos/common/cifs.nix**: Uses sops templates for SMB credential file generation

## Current Secrets

- `smb_username` / `smb_password` (`smb.yaml`) - SMB/CIFS credentials for NAS access
- `emil_password_hash` (`system.yaml`) - Hashed login password for the `emil` user, required at boot for user creation (decrypted to `/run/secrets-for-users/` because of `neededForUsers`)
- `luks_key` (`luks.yaml`) - LUKS disk encryption key, only used at install time (`scripts/pre-install-secrets.sh` decrypts it for disko); intentionally not declared in `sops.nix`, so it is never placed on the running system

## Troubleshooting

### Secret Not Decrypting

```bash
# Check if age key exists and is readable
ls -la ~/.config/sops/age/keys.txt

# Test decryption manually
cd secrets
sops -d smb.yaml
```

### System Build Failures

```bash
# Verify all secrets are properly encrypted
cd secrets
for file in *.yaml; do
    echo "Checking $file..."
    sops -d "$file" > /dev/null && echo "✓ OK" || echo "✗ FAILED"
done
```

### Template Generation Issues

```bash
# Check if secrets are mounted
ls -la /run/secrets/

# Check if templates are rendered
ls -la /run/secrets-rendered/

# View systemd logs
journalctl -u sops-nix.service
```

## Security Notes

- **Never commit unencrypted secrets** to git
- Age keys in `~/.config/sops/age/keys.txt` should be backed up securely (the canonical copy lives in the Bitwarden note `fw13-age-key`)
- Only encrypted secrets are committed to git
- Secrets are automatically decrypted at boot time by sops-nix
- User-level key storage keeps secrets accessible to your user account
