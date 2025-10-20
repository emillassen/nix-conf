{ pkgs, ... }:
{
  programs = {
    git = {
      enable = true;
      package = pkgs.git;

      # GPG signing
      signing = {
        key = "0F3E92F0DA4F2DD1";
        signByDefault = true;
      };

      settings = {
        user = {
          name = "Emil Lassen";
          email = "emil@emillassen.com";
        };

        # Modern Git defaults and other settings
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
        pull.rebase = true;
        merge.conflictstyle = "diff3";
        diff.colorMoved = "default";

        # Useful aliases
        alias = {
          st = "status";
          co = "checkout";
          cb = "checkout -b";
          br = "branch";
          lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
          unstage = "restore --staged";
        };
      };
    };

    delta = {
      enable = true;
      enableGitIntegration = true;
      options = {
        side-by-side = true;
        syntax-theme = "Catppuccin-mocha";
      };
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
