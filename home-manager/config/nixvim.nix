{ inputs, ... }:
{
  imports = [
    inputs.nixvim.homeModules.nixvim
  ];

  programs.nixvim = {
    enable = true;

    # General settings
    clipboard = {
      register = "unnamedplus";
      providers.wl-copy.enable = true;
    };

    opts = {
      # File handling
      swapfile = false;
      backup = false;

      # Line numbers
      number = true;
      relativenumber = true;

      # UI settings
      termguicolors = true;
      scrolloff = 8;
      signcolumn = "yes";
      updatetime = 50;

      # Search settings
      ignorecase = true;
      smartcase = true;
      incsearch = true;
      hlsearch = true;

      # Indentation
      tabstop = 4;
      shiftwidth = 4;
      expandtab = true;
      smarttab = true;

      # Better splits
      splitbelow = true;
      splitright = true;

      # Show whitespace characters
      list = true;
      listchars = "tab:> ,trail:-,nbsp:+";

      # Disable error bells
      errorbells = false;
    };

    # Color scheme
    colorschemes.catppuccin = {
      enable = true;
      settings.flavour = "mocha";
    };

    # Plugins
    plugins = {
      # Treesitter for better syntax highlighting
      treesitter = {
        enable = true;
        settings = {
          highlight.enable = true;
          indent.enable = true;
        };
      };

      # Git integration
      fugitive.enable = true;

      # Show keybindings
      which-key = {
        enable = true;
      };

      # Start screen
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
            {
              type = "group";
              val = [
                {
                  type = "button";
                  val = "  New file";
                  on_press.__raw = "function() vim.cmd[[enew]] end";
                  opts = {
                    shortcut = "n";
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

    # Keymaps
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
