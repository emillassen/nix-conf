{ config, pkgs, nixpkgs-unstable, ... }:

{
  programs = {
    zsh = {
      enable = true;
      package = pkgs.unstable.zsh;
      autocd = false;
      syntaxHighlighting.enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      history.save = 1000000;
      history.size = 1000000;
      plugins = [
        { name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme"; }
        { name = "powerlevel10k-config";
          src = ../zsh;
          file = "p10k.zsh"; }
      ];
      shellAliases = {
        "ll" = "ls -a";
        "c" = "clear";
        ".." = "cd ..";
        "g" = "git";
        "ga" = "git add";
        "gaa" = "git add --all";
        "gc" = "git commit";
        "gp" = "git push";
        "gs" = "git status";
        "lg" = "lazygit";
        "cat" = "bat";
        "nano" = "micro";
        "vim" = "nvim";
        "bottom" = "echo 'To run bottom, use the command btm'";
        "myip" = "curl ip.wtf/moo";
        "pocket-up" = "pupdate -s -p /run/media/$(whoami)/Pocket/";
        "cdnix" = "cd ~/Documents/nix-conf/";
        "nix-switch" = "sudo nixos-rebuild switch --flake ~/Documents/nix-conf#fw13";
        "nix-switchu" = "sudo nixos-rebuild switch --upgrade --flake ~/Documents/nix-conf#fw13";
        "nix-clean" = "sudo nix-collect-garbage -d && nix-collect-garbage -d && sudo nix-store --optimise";
        "flake-up" = "sudo nix flake update ~/Documents/nix-conf/";
      };
    };
  };
}
