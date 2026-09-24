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
        # oh-my-zsh comes from the personal fork (flake input `ohmyzsh`)
        # rather than nixpkgs' pin: its master is upstream plus the fixes
        # carried locally while they wait upstream -- currently the mise
        # plugin's completion job, which prompted on the terminal and left
        # ghostel panes without a visible cursor. Everything else about the
        # nixpkgs derivation (the $ZSH rewrite, disabled auto-update, the
        # unfunctioned self-updaters) still applies; only the source moves.
        package = pkgs.oh-my-zsh.overrideAttrs (_: {
          src = inputs.ohmyzsh;
          version = inputs.ohmyzsh.shortRev;
        });
        # The plugin list from dotfiles2 (the admin machine), minus two:
        # starship (hm's starship module injects the init itself) and z
        # (programs.zoxide below replaces it). Plugins for tools karma does
        # not ship are kept on purpose: they are inert without the tool and
        # keep the list in sync with the admin machine. The mise plugin
        # activates mise when the host installs it (see
        # modules/nixos/features/mise.nix).
        plugins = [
          "git"
          "cp"
          "gh"
          "sudo"
          "gpg-agent"
          "extract"
          "mise"
          "direnv"
          "tmux"
          "colored-man-pages"
          "history-substring-search"
          "fzf"
          "web-search"

          # emacs (lol)
          "emacs"

          # containers & infra
          "docker"
          "docker-compose"
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

    # Prompt (gruvbox powerline config carried over from dotfiles2).
    programs.starship.enable = true;
    xdg.configFile."starship.toml".source = ./shell/starship.toml;

    # Smarter cd; the module wires the zsh init the bare package lacked.
    programs.zoxide.enable = true;

    home.sessionPath = ["$HOME/bin"];

    # nano, as a default: homeModules.emacs overrides both with emacsclient on
    # hosts that run the emacs daemon. Headless hosts keep this --
    # nix-check-bin above shells out to $EDITOR.
    home.sessionVariables.EDITOR = lib.mkDefault (lib.getExe pkgs.nano);
    home.sessionVariables.VISUAL = lib.mkDefault (lib.getExe pkgs.nano);

    # Point Docker-API clients (testcontainers, Docker SDKs, act, IDE docker
    # plugins) at rootless podman's socket -- they'd otherwise probe
    # /var/run/docker.sock, which doesn't exist here (dockerCompat only ships
    # the `docker` CLI shim, and dockerSocket is off). The CLI shim and
    # podman-compose talk to podman directly and ignore this.
    # Set twice on purpose: home.sessionVariables reaches interactive shells,
    # systemd.user.sessionVariables reaches GUI apps started by the user
    # manager. Both expand $XDG_RUNTIME_DIR at read time, so no uid is baked in.
    home.sessionVariables.DOCKER_HOST = "unix://$XDG_RUNTIME_DIR/podman/podman.sock";
    systemd.user.sessionVariables.DOCKER_HOST = "unix://\${XDG_RUNTIME_DIR}/podman/podman.sock";

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
      # Doesn't need an explanation.
      openssl
      # OpenPGP encryption/signing (gpg, gpg-agent).
      gnupg

      ###
      ### media & images
      # Convert/resize/manipulate images from the CLI.
      imagemagick
      # Audio/video transcoding swiss army knife (also provides ffplay).
      ffmpeg-full
      # Download video/audio from the web.
      yt-dlp

      ###
      ### editing
      # nano for life.
      nano
      # Parser toolkit CLI; editors use it for grammars.
      tree-sitter
      # Document converter.
      pandoc
      # JSON processor.
      jq

      ###
      ### agentic coding harnesses
      # Auto-updated via the claude-code-nix flake.
      inputs.claude-code-nix.packages.${stdenv.hostPlatform.system}.claude-code
    ];
  };
}
