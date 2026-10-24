{ inputs, ... }:
{
  imports = [
    inputs.nixvim.homeModules.nixvim
  ];

  programs.nixvim = {
    enable = true;

    nixpkgs.source = inputs.nixpkgs;

    version.enableNixpkgsReleaseCheck = false;

    clipboard = {
      register = "unnamedplus";
      providers.wl-copy.enable = true;
    };

    opts = {
      swapfile = false;
      backup = false;

      # Treesitter folding (below) with every fold open when a file opens;
      # zc / zM close them on demand.
      foldlevelstart = 99;

      number = true;
      relativenumber = true;

      termguicolors = true;
      scrolloff = 8;
      signcolumn = "yes";
      updatetime = 50;

      ignorecase = true;
      smartcase = true;
      incsearch = true;
      hlsearch = true;

      tabstop = 4;
      shiftwidth = 4;
      expandtab = true;
      smarttab = true;

      splitbelow = true;
      splitright = true;

      list = true;
      listchars = "tab:> ,trail:-,nbsp:+";

      errorbells = false;
    };

    colorschemes.catppuccin = {
      enable = true;
      settings.flavour = "mocha";
    };

    plugins = {
      # Top-level options, not `settings`: with nvim-treesitter's main branch,
      # `settings` reaches only the legacy configs module, and folding there
      # did nothing at all (foldmethod stayed manual). highlight and indent
      # still worked through a compatibility shim nixvim marks for removal.
      treesitter = {
        enable = true;
        highlight.enable = true;
        indent.enable = true;
        folding.enable = true;
      };

      fugitive.enable = true;

      which-key = {
        enable = true;
      };

      alpha = {
        enable = true;
        settings = {
          layout = [
            {
              type = "padding";
              val = 2;
            }
            {
              type = "text";
              val = [
                "                                                     "
                "  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗ "
                "  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║ "
                "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║ "
                "  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║ "
                "  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║ "
                "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝ "
                "                                                     "
              ];
              opts = {
                position = "center";
                hl = "Title";
              };
            }
            {
              type = "padding";
              val = 2;
            }
            # `shortcut` is only the letter drawn beside a button; the key that
            # presses it is `keymap` (what alpha's dashboard.button() builds).
            # With shortcuts alone, the letters on screen did nothing.
            {
              type = "group";
              val = [
                {
                  type = "button";
                  val = "  New file";
                  on_press.__raw = "function() vim.cmd[[enew]] end";
                  opts = {
                    shortcut = "n";
                    keymap = [
                      "n"
                      "n"
                      "<Cmd>enew<CR>"
                      {
                        noremap = true;
                        silent = true;
                        nowait = true;
                      }
                    ];
                    position = "center";
                    cursor = 3;
                    width = 50;
                    align_shortcut = "left";
                    hl_shortcut = "Keyword";
                  };
                }
                {
                  type = "button";
                  val = "  Explore";
                  on_press.__raw = "function() vim.cmd[[Explore]] end";
                  opts = {
                    shortcut = "e";
                    keymap = [
                      "n"
                      "e"
                      "<Cmd>Explore<CR>"
                      {
                        noremap = true;
                        silent = true;
                        nowait = true;
                      }
                    ];
                    position = "center";
                    cursor = 3;
                    width = 50;
                    align_shortcut = "left";
                    hl_shortcut = "Keyword";
                  };
                }
                {
                  type = "button";
                  val = "  Recent files";
                  on_press.__raw = "function() vim.cmd[[browse oldfiles]] end";
                  opts = {
                    shortcut = "r";
                    keymap = [
                      "n"
                      "r"
                      "<Cmd>browse oldfiles<CR>"
                      {
                        noremap = true;
                        silent = true;
                        nowait = true;
                      }
                    ];
                    position = "center";
                    cursor = 3;
                    width = 50;
                    align_shortcut = "left";
                    hl_shortcut = "Keyword";
                  };
                }
                {
                  type = "button";
                  val = "  Git summary";
                  on_press.__raw = "function() vim.cmd[[Git | only]] end";
                  opts = {
                    shortcut = "g";
                    keymap = [
                      "n"
                      "g"
                      "<Cmd>Git | only<CR>"
                      {
                        noremap = true;
                        silent = true;
                        nowait = true;
                      }
                    ];
                    position = "center";
                    cursor = 3;
                    width = 50;
                    align_shortcut = "left";
                    hl_shortcut = "Keyword";
                  };
                }
                {
                  type = "button";
                  val = "  Scratchpad";
                  on_press.__raw = "function() vim.cmd[[e ~/Documents/scratch.md]] end";
                  opts = {
                    shortcut = "s";
                    keymap = [
                      "n"
                      "s"
                      "<Cmd>e ~/Documents/scratch.md<CR>"
                      {
                        noremap = true;
                        silent = true;
                        nowait = true;
                      }
                    ];
                    position = "center";
                    cursor = 3;
                    width = 50;
                    align_shortcut = "left";
                    hl_shortcut = "Keyword";
                  };
                }
                {
                  type = "button";
                  val = "  Nix config flake";
                  on_press.__raw = "function() vim.cmd[[e ~/Documents/nix-conf/flake.nix]] end";
                  opts = {
                    shortcut = "c";
                    keymap = [
                      "n"
                      "c"
                      "<Cmd>e ~/Documents/nix-conf/flake.nix<CR>"
                      {
                        noremap = true;
                        silent = true;
                        nowait = true;
                      }
                    ];
                    position = "center";
                    cursor = 3;
                    width = 50;
                    align_shortcut = "left";
                    hl_shortcut = "Keyword";
                  };
                }
                {
                  type = "button";
                  val = "  Tutor";
                  on_press.__raw = "function() vim.cmd[[Tutor]] end";
                  opts = {
                    shortcut = "t";
                    keymap = [
                      "n"
                      "t"
                      "<Cmd>Tutor<CR>"
                      {
                        noremap = true;
                        silent = true;
                        nowait = true;
                      }
                    ];
                    position = "center";
                    cursor = 3;
                    width = 50;
                    align_shortcut = "left";
                    hl_shortcut = "Keyword";
                  };
                }
                {
                  type = "button";
                  val = "  Quit nvim";
                  on_press.__raw = "function() vim.cmd[[qa]] end";
                  opts = {
                    shortcut = "q";
                    keymap = [
                      "n"
                      "q"
                      "<Cmd>qa<CR>"
                      {
                        noremap = true;
                        silent = true;
                        nowait = true;
                      }
                    ];
                    position = "center";
                    cursor = 3;
                    width = 50;
                    align_shortcut = "left";
                    hl_shortcut = "Keyword";
                  };
                }
              ];
            }
          ];
        };
      };
    };

    keymaps = [
      {
        mode = "n";
        key = "<space>G";
        action = "<cmd>Git<CR>";
        options = {
          desc = "Open Git";
        };
      }
      {
        mode = "n";
        key = "<space>a";
        action = "<cmd>Alpha<CR>";
        options = {
          desc = "Open alpha dashboard";
        };
      }
    ];
  };
}
