{inputs, ...}: {
  flake.homeModules.shell = {
    config,
    lib,
    pkgs,
    ...
  }: let
    nix-check-bin = pkgs.writeShellApplication {
      name = "nix-check-bin";
      text = ''
        $EDITOR "$(nix build "$1" --no-link --print-out-paths)/bin"
      '';
    };
  in {
    # Plain zsh as the login shell; hm owns ~/.zshrc and ~/.zshenv directly
    # (the ZDOTDIR-redirect wrapper from modules/wrappedPrograms/ is gone).
    programs.zsh = {
      enable = true;
      # Keep the dotfiles at ~/ and silence the upstream default-change
      # warning.
      dotDir = config.home.homeDirectory;
      # No theme set: the prompt comes from starship (below), which runs
      # after oh-my-zsh's init and overrides any OMZ prompt.
      oh-my-zsh = {
        enable = true;
        # The plugin list from dotfiles2 (the admin machine), minus two:
        # starship (hm's starship module injects the init itself) and z
        # (programs.zoxide below replaces it). Plugins for tools karma does
        # not ship are kept on purpose: they are inert without the tool and
        # keep the list in sync with the admin machine. The mise plugin
        # activates mise when the host installs it (see
        # modules/nixos/features/mise.nix).
        plugins = [
          "git"
          "gh"
          "sudo"
          "gpg-agent"
          "extract"
          "mise"
          "direnv"
          "tmux"
          "task"
          "colored-man-pages"
          "history-substring-search"
          "fzf"
          "web-search"

          # languages
          "ruby"
          "rails"
          "golang"

          # emacs
          "emacs"
          "cask"

          # containers & infra
          "docker"
          "docker-compose"
          "terraform"
          "opentofu"
          "kubectl"

          # clouds
          "aws"
          "azure"
          "gcloud"
        ];
        # Auto-sourced *.zsh drop-in dir; the ghostel/emacs integration
        # below lands there.
        custom = "${config.xdg.configHome}/omz";
        extraConfig = ''
          COMPLETION_WAITING_DOTS="true"
          HIST_STAMPS="yyyy-mm-dd"
        '';
      };
    };

    # Terminal commands drive the running Emacs when inside a ghostel
    # terminal; sourced by oh-my-zsh from the custom dir above.
    xdg.configFile."omz/emacs.zsh".source = ./shell/emacs.zsh;

    # Prompt (gruvbox powerline config carried over from dotfiles2).
    programs.starship.enable = true;
    xdg.configFile."starship.toml".source = ./shell/starship.toml;

    # Smarter cd; the module wires the zsh init the bare package lacked.
    programs.zoxide.enable = true;

    home.sessionPath = ["$HOME/bin"];

    home.sessionVariables.EDITOR = lib.getExe pkgs.nano;

    # The CLI toolchain, previously baked into the wrapped shell's PATH;
    # the per-user profile now carries it.
    home.packages = with pkgs; [
      ###
      ### nix tooling
      # Search NixOS/home-manager option and nixpkgs function docs from the CLI.
      manix
      # TUI for browsing flake outputs and config attrsets as a tree.
      nix-inspect
      # Nix helper: nicer rebuild diffs, generation cleanup, search.
      nh
      # Open a freshly built derivation's bin/ in $EDITOR (defined above).
      nix-check-bin

      ###
      ### dev environments & containers
      # Reproducible per-project dev shells (this repo's .envrc uses it).
      devenv
      # docker-compose-style workflows on top of podman.
      podman-compose

      ###
      ### version control
      git
      # TUI frontend for git.
      lazygit
      # GitHub CLI.
      gh

      ###
      ### build systems
      gnumake
      cmake

      ###
      ### shell navigation & search
      # Fuzzy finder for anything line-based (files, history, pids).
      fzf
      # Modern ls replacement.
      eza
      # Modern find replacement.
      fd
      # Fast recursive grep.
      ripgrep

      ###
      ### system & processes
      # Symlink-farm manager; deploys hand-managed dotfiles (e.g. ~/.emacs.d
      # from a dotfiles checkout) without hm involvement.
      stow
      # Interactive process viewer.
      htop
      # Fancier resource monitor.
      btop
      # Kill processes by name.
      killall
      # System info splash for the terminal.
      fastfetch
      # Disk usage as a readable tree (du replacement).
      dust
      # Identify what a file actually is.
      file

      ###
      ### archives
      unzip
      zip
      p7zip

      ###
      ### network & remote
      # Non-interactive downloader.
      wget
      # Mount remote directories over ssh.
      sshfs
      # Run remote Wayland GUI apps over ssh.
      waypipe

      ###
      ### media & images
      # Convert/resize/manipulate images from the CLI.
      imagemagick
      # Minimal Wayland image viewer.
      imv
      # Video player.
      mpv
      # Audio/video transcoding swiss army knife (also provides ffplay).
      ffmpeg-full
      # Download video/audio from the web.
      yt-dlp

      ###
      ### editing & clipboard
      # $EDITOR (see home.sessionVariables above).
      nano
      # wl-copy/wl-paste for the Wayland clipboard.
      wl-clipboard
      # Parser toolkit CLI; editors use it for grammars.
      tree-sitter

      ###
      ### agentic coding harnesses
      # Auto-updated via the claude-code-nix flake.
      inputs.claude-code-nix.packages.${stdenv.hostPlatform.system}.claude-code
    ];
  };
}
