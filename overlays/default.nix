# This file defines overlays
{ inputs, ... }:
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://wiki.nixos.org/wiki/Overlays
  modifications = final: prev: {
    # nixpkgs' filebot is months behind upstream, and the package adds a
    # desktop entry on top; both live in pkgs/filebot. `prev.filebot` is passed
    # explicitly because the argument of that name would otherwise resolve to
    # this very attribute.
    filebot = final.callPackage ../pkgs/filebot { inherit (prev) filebot; };
  };

  # When applied, the stable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.stable'
  stable-packages = final: _prev: {
    stable = import inputs.nixpkgs-stable {
      # pass the plain system string — handing unstable's elaborated
      # hostPlatform to a different nixpkgs version (as localSystem) makes its
      # stdenv bootstrap think it's cross-compiling → infinite recursion
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  };
}
