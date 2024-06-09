# Git is needed for home-manager to work
{
  config,
  pkgs,
  nixpkgs-unstable,
  ...
}: {
  # Enable git and basic config
  programs = {
    git = {
      enable = true;
      package = pkgs.unstable.git;
      userName = "Emil Lassen";
      userEmail = "155289+emillassen@users.noreply.github.com";
    };
    gh = {
      enable = true;
      settings = {
        version = "1";
        git_protocol = "ssh";
        prompt = "enabled";
      };
    };
  };
}
