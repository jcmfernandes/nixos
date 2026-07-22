{
  flake.homeModules.desktop-session = {
    lib,
    pkgs,
    ...
  }: {
    # The wrapped zsh (modules/wrappedPrograms/zsh.nix) points ZDOTDIR at the
    # store; its store-side .zshenv/.zshrc source the user's ~/.zshenv and
    # ~/.zshrc, which home-manager manages here.
    home.file.".zshenv".text = ''
      export EDITOR="${lib.getExe pkgs.nano}"
    '';

    # Interactive-only init. Activate mise for per-project tool versions when
    # the host installs it (see modules/nixos/features/mise.nix); no-op
    # otherwise.
    home.file.".zshrc".text = ''
      command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"
    '';
  };
}
