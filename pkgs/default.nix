# Custom packages, that can be defined similarly to ones from nixpkgs
# You can refer to packages from anywhere on your home-manager/nixos configurations,
# build them with nix build .#package-name, or bring them into your shell with nix shell .#package-name
pkgs: {
  # example = pkgs.callPackage ./example { };
  drtv-dl = pkgs.callPackage ./drtv-dl { };
  standardebooks-dl = pkgs.callPackage ./standardebooks-dl { };
  vuescan = pkgs.callPackage ./vuescan { };
  devilutionx = pkgs.callPackage ./devilutionx { };
  # ./filebot overrides nixpkgs' filebot instead of adding one, so it is applied
  # by the `modifications` overlay. Listing it here would make the `additions`
  # overlay resolve its own `filebot` argument — infinite recursion.
}
