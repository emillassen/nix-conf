{ pkgs, ... }:
{
  programs = {
    zsh = {
      enable = true;
      package = pkgs.zsh;
      autocd = false;
      syntaxHighlighting.enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      history.save = 1000000;
      history.size = 1000000;
      plugins = [
        {
          name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }
        {
          name = "powerlevel10k-config";
          src = ../zsh;
          file = "p10k.zsh";
        }
      ];
      zsh-abbr = {
        enable = true;
        abbreviations = {
          ll = "ls -a";
          c = "clear";
          ".." = "cd ..";
          vim = "nvim";
          bottom = "echo 'To run bottom, use the command btm'";
          myip = "curl ip.wtf/moo";
          pupdate = "pocket-up";
          pocket-up = "pupdate -s -p /run/media/$(whoami)/Pocket/";
          ns = "sudo nixos-rebuild switch --flake $NH_FLAKE#fw13";
          nsu = "sudo nixos-rebuild switch --upgrade --flake $NH_FLAKE#fw13";
          nix-clean = "sudo nix-collect-garbage -d && sudo nix-store --optimise";
          flake-up = "nix flake update --flake $NH_FLAKE";
        };
      };
    };
  };
}
