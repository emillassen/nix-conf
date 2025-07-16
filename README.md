# My NixOS config using Flakes and Home Manager

## Initial installation on a new device

1. Boot from a USB stick with the latest NixOS release
2. Change keyboard layout to match device and test that it is correct
3. Logon to Wi-Fi
4. `cd /tmp`
5. `git clone https://github.com/emillassen/nix-conf.git`
6. `cd nix-conf`
7. Run `./scripts/setup-age-key.sh` to fetch your age key from Bitwarden.
8. `sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko /tmp/nix-conf/nixos/disks.nix`
9. `sudo nixos-install --root /mnt --flake /tmp/nix-conf#fw13 --no-root-passwd`
10. Select `y` to everything
11. Restart and remove the USB stick

## First boot setup

1. Logon to Wi-Fi
2. `cd ~/Documents`
3. `git clone https://github.com/emillassen/nix-conf.git`
4. `cdnix && git remote set-url origin git@github.com:emillassen/nix-conf.git`
5. Enroll fingerprints using `fprintd-enroll`
6. Run `./scripts/setup-yubikey.sh` to automate the YubiKey SSH setup process.

### KDE changes

1. Create KDE Wallet with empty password
1. Right-click battery in system tray and tick show battery percentage
1. Import window rules under Settings -> Window Management -> Window Rules
1. Settings -> Quick Settings -> Theme -> Breeze Dark
1. Settings -> Display Configuration -> Scale -> 125 %
1. Settings -> Display Configuration -> Color Profile -> ICC Profile
1. Settings -> Mouse & Touchpad -> Touchpad -> Scrolling -> Invert scroll direction
1. Settings -> Mouse & Touchpad -> Touchpad -> Scrolling speed -> 4th tick
1. Settings -> Mouse & Touchpad -> Touchpad -> Right-click -> Press anywhere with two fingers
1. Settings -> Mouse & Touchpad -> Screen Edges -> Maximize -> Untick
1. Settings -> Apperance & Style -> Text & Fonts -> Sub-pixel rendering -> RGB
1. Settings -> Apperance & Style -> Colors & Themes -> Colors -> Get New.. -> Catppuccin Mocha Colors by Catppuccin
1. Settings -> Apperance & Style -> Colors & Themes -> Window Decorations -> Get New.. -> Scratchy by jomada
1. Settings -> Apperance & Style -> Colors & Themes -> Icons -> Get New.. -> Papirus by x-varlesh-x
1. Settings -> Workspace -> General Behavior -> Animation speed -> 11th tick
1. Settings -> Window Management -> Window Behavior -> Movement -> Screen edge and window snap zone: 5 px
1. Settings -> Window Management -> Desktop Effects -> Screed Edge -> Untick
1. Virtual Desktops -> Create 3 -> (Main, IT, Misc)
1. Virtual Desktops -> Show animation when switching -> Cog -> Gap between desktops -> Horizontal & Vertical -> 0

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
