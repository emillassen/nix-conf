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
        {
          name = "zsh-abbr";
          src = pkgs.zsh-abbr;
          file = "share/zsh/site-functions/abbr";
        }
      ];
      initExtra = ''
        # Initialize abbreviations
        abbr ll="ls -a"
        abbr c="clear"
        abbr ..="cd .."
        abbr vim="nvim"
        abbr bottom="echo 'To run bottom, use the command btm'"
        abbr myip="curl ip.wtf/moo"
        abbr pupdate="pocket-up"
        abbr pocket-up="pupdate -s -p /run/media/$(whoami)/Pocket/"
        abbr nix-switch="sudo nixos-rebuild switch --flake ~/Documents/nix-conf#fw13"
        abbr nix-switchu="sudo nixos-rebuild switch --upgrade --flake ~/Documents/nix-conf#fw13"
        abbr nix-clean="sudo nix-collect-garbage -d && nix-collect-garbage -d && sudo nix-store --optimise"
        abbr flake-up="nix flake update --flake ~/Documents/nix-conf/"
      '';
    };
  };
}
