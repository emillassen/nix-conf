# My NixOS config using Flakes and Home Manager

# Initial setup for a new device
1. Install the latest NixOS release (remember to allow unfree packages and name the user `emil`)
1. `nix-shell -p git`
1. `cd ~/Documents/`
1. `git clone https://github.com/emillassen/nix-conf.git`
1. `cp /etc/nixos/hardware-configuration.nix ~/Documents/nix-conf/nixos/` replacing the downloaded `hardware-configuration.nix`
1. `sudo nixos-rebuild switch --upgrade --flake ~/Documents/nix-conf#fw13`
1. `reboot`
1. `cdnix && git remote set-url origin git@github.com:emillassen/nix-conf.git`

## Manual changes
1. Enroll fingerprints using `fprintd-enroll`
1. Login to Nextcloud Desktop client

### GNOME changes
1. `gsettings set org.gnome.desktop.interface color-scheme prefer-dark`
1. `gsettings set org.gnome.desktop.interface show-battery-percentage true`
1. `gsettings set org.gnome.desktop.interface text-scaling-factor 1.25`
1. `gsettings set org.gnome.desktop.peripherals.touchpad speed 0.1`
1. `gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true`
1. `gsettings set org.gnome.desktop.peripherals.mouse accel-profile flat`
1. `gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']"`
1. `gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false`
1. `gsettings set org.gnome.settings-daemon.plugins.power idle-dim false`

### YubiKey Setup
1. Download pub.asc from Bitwarden
1. Run the following commands: 
```
cd ~/Downloads/
gpg --keyid-format 0xlong --import pub.asc
gpg --keyid-format 0xlong --card-status
KEY_ID=0x0000000000000000 (the sec# key)
ssh-add -L | awk  '{print $1 " " $2 " emil@emillassen.com"}' | tee ~/.ssh/emillassen.pub
chmod 0600 ~/.ssh/emillassen.pub
```

### Display color profile
1. Download the .icc profile from https://www.notebookcheck.net/Framework-Laptop-13-5-Ryzen-7-7840U-review-So-much-better-than-the-Intel-version.756613.0.html
1. Run the following commands:
```
cd ~/Downloads/
colormgr import-profile BOE_CQ_______NE135FBM_N41_03.icm
colormgr get-devices
colormgr get-profiles
colormgr device-add-profile `Device ID` `Profile ID`
```
3. Go to Settings -> Color, select the new color profile, and enable it for all users
