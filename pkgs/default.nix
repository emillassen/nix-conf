# Custom packages, that can be defined similarly to ones from nixpkgs
# You can refer to packages from anywhere on your home-manager/nixos configurations,
# build them with nix build .#package-name, or bring them into your shell with nix shell .#package-name
pkgs: {
  # example = pkgs.callPackage ./example { };
  vuescan = pkgs.callPackage ./vuescan { inherit (pkgs) lib; };
}
