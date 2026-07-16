{ lib, ... }:
{
  programs = {
    # Prompt. The Catppuccin module (config/catppuccin.nix autoEnable) injects
    # the Mocha palette, so the palette color names below resolve to Mocha hex.
    starship = {
      enable = true;
      settings = {
        # Single-line prompt, no leading blank line.
        add_newline = false;
        format = lib.concatStrings [
          "$username"
          "$hostname"
          "$directory"
          "$git_branch"
          "$git_state"
          "$git_status"
          "$nix_shell"
          "$container"
          "$direnv"
          "$rust"
          "$python"
          "$nodejs"
          "$golang"
          "$jobs"
          "$cmd_duration"
          "$character"
        ];
        # Shown only when relevant (root, or over SSH) so local prompts stay clean.
        username = {
          style_user = "bold teal";
          style_root = "bold red";
          show_always = false;
        };
        hostname = {
          ssh_only = true;
          style = "bold teal";
          format = "on [$hostname]($style) ";
        };

        directory = {
          style = "bold lavender";
          truncation_length = 3;
          truncate_to_repo = true;
          truncation_symbol = "…/";
          read_only = " ";
        };

        character = {
          success_symbol = "[❯](bold green)";
          error_symbol = "[❯](bold red)";
          vimcmd_symbol = "[❮](bold green)";
        };

        git_branch = {
          symbol = " ";
          style = "bold mauve";
        };
        # Rebase/merge/cherry-pick in progress, with step progress (e.g. 3/7).
        git_state = {
          style = "bold red";
          format = "[\\($state( $progress_current/$progress_total)\\)]($style) ";
        };
        git_status = {
          style = "bold peach";
          # Compact counts: conflicts, ahead/behind, staged, modified, untracked.
          conflicted = "=";
          ahead = "⇡\${count}";
          behind = "⇣\${count}";
          diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
          staged = "[+\${count}](green)";
          modified = "!\${count}";
          untracked = "?\${count}";
          stashed = "\\$\${count}";
          deleted = "✘\${count}";
        };

        nix_shell = {
          symbol = " ";
          style = "bold sky";
          format = "via [$symbol$name]($style) ";
        };

        # Shown when inside a toolbox/distrobox/docker shell; invisible otherwise.
        container = {
          symbol = " ";
          style = "bold yellow";
          format = "[$symbol\\[$name\\]]($style) ";
        };

        # .envrc load status — handy alongside Nix flakes / dev shells.
        direnv = {
          disabled = false;
          symbol = " ";
          style = "bold sky";
          format = "[$symbol$loaded]($style) ";
        };

        # Language runtime versions: only render inside a matching project dir.
        rust = {
          symbol = " ";
          style = "bold red";
          format = "via [$symbol$version]($style) ";
        };
        python = {
          symbol = " ";
          style = "bold yellow";
          format = "via [$symbol$version]($style) ";
        };
        nodejs = {
          symbol = " ";
          style = "bold green";
          format = "via [$symbol$version]($style) ";
        };
        golang = {
          symbol = " ";
          style = "bold sky";
          format = "via [$symbol$version]($style) ";
        };

        # Visual reminder that sudo credentials are currently cached. Disabled:
        # the status check cost ~14ms per prompt render for a cosmetic glyph.
        sudo = {
          disabled = true;
          symbol = " ";
          style = "bold red";
          format = "[as $symbol]($style)";
        };

        # Count of backgrounded jobs; only shown when there is at least one.
        jobs = {
          symbol = " ";
          style = "bold blue";
        };

        cmd_duration = {
          min_time = 2000; # only show for commands slower than 2s
          style = "bold yellow";
          format = "took [$duration]($style) ";
        };

        # Right-aligned clock disabled — prompt no longer uses a right_format.
        time = {
          disabled = true;
          style = "bold overlay1";
          format = "[$time]($style)";
          time_format = "%R";
        };
      };
    };

    zsh = {
      enable = true;
      autocd = false;
      syntaxHighlighting.enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      # Cache the completion dump and only run the full audit/rebuild once a day.
      # The default bare `compinit` recompiles every launch because NixOS fpath
      # store paths change on each rebuild — that dominated shell startup time.
      # Tradeoff: completions from a fresh nixos-rebuild may not appear until the
      # next daily full init (or a manual `compinit`).
      completionInit = ''
        autoload -Uz compinit
        _zcompdump="$HOME/.cache/zsh/zcompdump"
        [[ -d "$HOME/.cache/zsh" ]] || mkdir -p "$HOME/.cache/zsh"
        if [[ -n "$_zcompdump"(#qN.mh+24) ]]; then
          compinit -d "$_zcompdump"
        else
          compinit -C -d "$_zcompdump"
        fi
      '';
      history = {
        save = 1000000;
        size = 1000000;
        # Drop older duplicate entries first and skip writing dups.
        ignoreDups = true;
        expireDuplicatesFirst = true;
      };
      # Print a blank line before each prompt to separate command output, but
      # skip it for the very first prompt so a fresh terminal has no leading gap.
      #
      # On the first prompt we also disable prompt_sp/prompt_cr: zsh's partial-
      # line marker fills row 0 with spaces, and Ghostty's OSC 133;A fresh-line
      # ("cl=line") then sees that row as non-empty and pushes the prompt down a
      # row — a spurious leading blank line. Re-enabled from the second prompt on
      # so the partial-output marker still works between commands.
      initContent = ''
        _blank_line_before_prompt() {
          if [[ -n "$_SEEN_FIRST_PROMPT" ]]; then
            print ""
            setopt prompt_sp prompt_cr
          else
            unsetopt prompt_sp prompt_cr
          fi
          _SEEN_FIRST_PROMPT=1
        }
        autoload -Uz add-zsh-hook
        add-zsh-hook precmd _blank_line_before_prompt
      '';
      zsh-abbr = {
        enable = true;
        abbreviations = {
          ll = "ls -la";
          c = "clear";
          ".." = "cd ..";
          vim = "nvim";
          bottom = "echo 'To run bottom, use the command btm'";
          myip = "curl ip.wtf/moo";
          pupdate = "pocket-up";
          pocket-up = "pupdate -s -p /run/media/$(whoami)/Pocket/";
          ns = "sudo nixos-rebuild switch --flake $NH_FLAKE#fw13";
          # -u updates flake inputs before switching (nixos-rebuild --upgrade
          # only updates channels, so it was a no-op with flakes)
          nsu = "nh os switch -u";
          # Bare `nh clean all` keeps only 1 generation — no rollback left.
          # Keep a margin on manual cleans; the weekly timer keeps 10/30d.
          nix-clean = "nh clean all --keep 5 --keep-since 7d";
          flake-up = "nix flake update --flake $NH_FLAKE";
        };
      };
    };
  };
}
