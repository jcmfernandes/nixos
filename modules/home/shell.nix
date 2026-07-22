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
    home.packages = [
      # nix
      pkgs.nil
      pkgs.nixd
      pkgs.statix
      pkgs.alejandra
      pkgs.manix
      pkgs.nix-inspect
      pkgs.nh
      pkgs.devenv
      pkgs.podman-compose

      # other
      pkgs.file
      pkgs.unzip
      pkgs.zip
      pkgs.p7zip
      pkgs.wget
      pkgs.killall
      pkgs.sshfs
      pkgs.fzf
      pkgs.htop
      pkgs.btop
      pkgs.eza
      pkgs.fd
      pkgs.zoxide
      pkgs.dust
      pkgs.ripgrep
      pkgs.fastfetch
      pkgs.tree-sitter
      pkgs.imagemagick
      pkgs.imv
      pkgs.mpv
      pkgs.ffmpeg-full
      pkgs.yt-dlp
      pkgs.lazygit

      # terminal multiplexers
      pkgs.zellij
      pkgs.tmux

      # AI coding agent, auto-updated via the claude-code-nix flake
      inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.claude-code

      pkgs.git
      pkgs.gnumake
      pkgs.nano
      pkgs.wl-clipboard
      pkgs.waypipe

      nix-check-bin
    ];
  };
}
