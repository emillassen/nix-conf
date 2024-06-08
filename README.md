# My NixOS config using Flakes and Home Manager

# Initial setup for a new device
1. Boot from a USB stick with the latest NixOS GNOME release
1. Open Settings -> Keyboard -> Input Sources -> Add Input Source -> Select the desired language
1. Select the language in the top right corner and test if the keyboard mappings are correct
1. `cd /tmp`
1. `nix-shell -p git`
1. `git clone https://github.com/emillassen/nix-conf.git`
1. `cd nix-conf/nixos`
1. Delete everything using GParted on nvme0n1
1. `nano -L /tmp/secret.key`
1. Enter the desired password for LUKS encryption and save the file
1. `cat secret.key` to make sure that the output matches your desired password and that it is without any trailing linebreaks
1. `sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko /tmp/nix-conf/nixos/disks.nix`
1. `sudo nixos-install --root /mnt --flake /tmp/nix-conf#fw13 --no-root-passwd`
1. Select `y` to everything
1. Enter a new password for the root user
1. restart and remove the USB stick
1. Logon to Wi-Fi
1. `su - root PASSWORD`
1. `passwd USERNAME`
1. `exit`
1. `cd ~/Documents`
1. `git clone https://github.com/emillassen/nix-conf.git`
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
