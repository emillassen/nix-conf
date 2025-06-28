{
  config,
  pkgs,
  ...
}:
{
  services.nextcloud-client = {
    enable = true;
    package = pkgs.nextcloud-client;
    startInBackground = true;
  };
}
# Currently bugged and does not autostart due to the following:
# https://github.com/nix-community/home-manager/issues/3562
# https://github.com/NixOS/nixpkgs/issues/206630
