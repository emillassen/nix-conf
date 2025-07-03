{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    package = pkgs.neovim-unwrapped;
    extraConfig = ''
      " General settings
      set clipboard=unnamed,unnamedplus
      set noswapfile nobackup
      set number relativenumber
      set noerrorbells
      set list listchars=tab:>\ ,trail:-,nbsp:+

      " Search settings
      set ignorecase smartcase
      set incsearch hlsearch
        
      " Indentation (consider using vim-sleuth for auto-detection)
      set tabstop=4 shiftwidth=4 expandtab smarttab
        
      " UI settings
      set termguicolors
      set scrolloff=8
      set signcolumn=yes
      set updatetime=50
       
      " Better splits
      set splitbelow splitright
    '';

    plugins = with pkgs.vimPlugins; [
      {
        plugin = nvim-treesitter.withAllGrammars;
        type = "lua";
        config = ''
          require'nvim-treesitter.configs'.setup {
            highlight = {
              enable = true,
              additional_vim_regex_highlighting = false,
            },
          }
        '';
      }
      {
        plugin = catppuccin-nvim;
        type = "lua";
        config = ''
          vim.cmd.colorscheme "catppuccin-mocha"
        '';
      }
      {
        plugin = vim-fugitive;
        type = "viml";
        config =
          # vim
          ''
            nmap <space>G :Git<CR>
          '';
      }
      {
        plugin = which-key-nvim;
        type = "lua";
        config =
          # lua
          ''
            require('which-key').setup{}
          '';
      }
      {
        plugin = alpha-nvim;
        type = "lua";
        config =
          # lua
          ''
            local alpha = require("alpha")
            local dashboard = require("alpha.themes.dashboard")

            dashboard.section.header.val = {
              "                                                     ",
              "  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗ ",
              "  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║ ",
              "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║ ",
              "  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║ ",
              "  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║ ",
              "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝ ",
              "                                                     ",
            }
            dashboard.section.header.opts.hl = "Title"

            dashboard.section.buttons.val = {
              dashboard.button( "n", "󰈔 New file" , ":enew<CR>"),
              dashboard.button( "e", " Explore", ":Explore<CR>"),
              dashboard.button( "r", " Recent files", ":browse oldfiles<CR>"),
              dashboard.button( "g", " Git summary", ":Git | :only<CR>"),
              dashboard.button( "s", " Scratchpad", ":e ~/Documents/scratch.md<CR>"),
              dashboard.button( "c", " Nix config flake", ":e ~/Documents/nix-config/flake.nix<CR>"),
              dashboard.button( "t", "󱛉 Tutor", ":Tutor<CR>"),
              dashboard.button( "q", "󰅙 Quit nvim", ":qa<CR>"),
            }

            alpha.setup(dashboard.opts)
            vim.keymap.set("n", "<space>a", ":Alpha<CR>", { desc = "Open alpha dashboard" })
          '';
      }
    ];
  };
}
