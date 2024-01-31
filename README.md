# My NixOS config using Flakes and Home Manager

## Manual stuff

### Color Manager
```
Download the .icc profile from https://www.notebookcheck.net/Framework-Laptop-13-5-Ryzen-7-7840U-review-So-much-better-than-the-Intel-version.756613.0.html
colormgr import-profile BOE_CQ_NE135FBM_N41_03.icm
colormgr get-devices
colormgr get-profiles
colormgr device-add-profile xrandr-BOE-0x0bca-0x00000000 icc-eca2e6d155d550a5e78c97a34ac3fcae
```

### Yubikey
```
download pub.asc from bitwarden
gpg --keyid-format 0xlong --import pub.asc
gpg --keyid-format 0xlong --card-status
KEY_ID=0x0000000000000000 (the sec# key)
mkdir ~/.ssh
chmod 0700 ~/.ssh
ssh-add -L | awk  '{print $1 " " $2 " emil@emillassen.com"}' | tee ~/.ssh/emillassen.pub
chmod 0600 ~/.ssh/emillassen.pub
```
