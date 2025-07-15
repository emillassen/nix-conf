{ pkgs, ... }:
{
  programs = {
    git = {
      enable = true;
      package = pkgs.git;
      userName = "Emil Lassen";
      userEmail = "emil@emillassen.com";

      # GPG signing
      signing = {
        key = "0F3E92F0DA4F2DD1";
        signByDefault = true;
      };

      # Modern Git defaults and other settings
      extraConfig = {
        init.defaultBranch = "main";
        push.autoSetupRemote = true;
        pull.rebase = true;
        merge.conflictstyle = "diff3";
        diff.colorMoved = "default";
      };

      # Useful aliases
      aliases = {
        st = "status";
        co = "checkout";
        cb = "checkout -b";
        br = "branch";
        lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        unstage = "restore --staged";
      };

      # Delta for better diffs
      delta = {
        enable = true;
        options = {
          side-by-side = true;
          syntax-theme = "Catppuccin-mocha";
        };
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
