{
  lib,
  inputs,
  self,
  ...
}: {
  perSystem = {
    pkgs,
    self',
    ...
  }: {
    # My whole desktop in one package, includes kityy terminal
    packages.desktop =
      (inputs.wrappers.wrapperModules.niri.apply ({config, ...}: {
        inherit pkgs;
        imports = [self.wrapperModules.niri];
        terminal = lib.getExe self'.packages.terminal;
        env = {
          EDITOR = lib.getExe pkgs.nano;
        };
      })).wrapper;

    # My primary flake terminal
    packages.terminal =
      (inputs.wrappers.wrapperModules.kitty.apply {
        inherit pkgs;
        imports = [self.wrapperModules.kitty];
        shell = lib.getExe self'.packages.environment;
      }).wrapper;

    # My primary flake shell with all of it's packages
    packages.environment = self'.packages.myZsh.override {
      runtimeInputs = [
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
        pkgs.sshfs
        pkgs.nano
        pkgs.wl-clipboard
        pkgs.waypipe

        # wrapped
#        self'.packages.neovimDynamic
#        self'.packages.qalc
#        self'.packages.lf
#        self'.packages.git
#        self'.packages.jujutsu
#        self'.packages.jjui
        self'.packages.nix-check-bin
      ];
      editor = lib.getExe pkgs.nano;
      # Activate mise for per-project tool versions when the host installs it
      # (see modules/nixos/features/mise.nix); no-op otherwise.
      interactiveInit = ''command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"'';
    };

    packages.nix-check-bin = pkgs.writeShellApplication {
      name = "nix-check-bin";
      text = ''
        $EDITOR "$(nix build "$1" --no-link --print-out-paths)/bin"
      '';
    };
  };
}