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
      # nix
      manix
      nix-inspect
      nh
      devenv
      podman-compose

      # other
      file
      unzip
      zip
      p7zip
      wget
      killall
      sshfs
      fzf
      htop
      btop
      eza
      fd
      zoxide
      dust
      ripgrep
      fastfetch
      tree-sitter
      imagemagick
      imv
      mpv
      ffmpeg-full
      yt-dlp
      lazygit

      # terminal multiplexers
      zellij
      tmux

      # AI coding agent, auto-updated via the claude-code-nix flake.
      inputs.claude-code-nix.packages.${stdenv.hostPlatform.system}.claude-code

      git
      gnumake
      cmake
      nano
      wl-clipboard
      waypipe

      nix-check-bin
    ];
  };
}
