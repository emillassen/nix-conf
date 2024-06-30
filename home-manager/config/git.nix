# Git is needed for home-manager to work
{
  config,
  pkgs,
  ...
}: {
  # Enable git and basic config
  programs = {
    git = {
      enable = true;
      package = pkgs.git;
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
