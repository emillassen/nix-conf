{
  config,
  pkgs,
  ...
}: {
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty;
    enableZshIntegration = true;
    settings = {
      theme = "catppuccin-mocha";
      font-size = 10;
    };
  };
}
