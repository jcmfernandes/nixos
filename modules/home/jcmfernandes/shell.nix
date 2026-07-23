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
      # Interactive-only init. Activate mise for per-project tool versions
      # when the host installs it (see modules/nixos/features/mise.nix);
      # no-op otherwise.
      initContent = ''
        command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"
      '';
    };

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
      # Smarter cd that jumps to frecently used directories.
      zoxide
      # Fast recursive grep.
      ripgrep

      ###
      ### system & processes
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
      ### terminal multiplexers
      zellij
      tmux

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
