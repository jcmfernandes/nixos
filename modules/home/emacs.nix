{
  flake.homeModules.emacs = {pkgs, ...}: {
    # Plain Wayland-native emacs. The old custom configure-flag build
    # (features/emacs.nix) was deliberately dropped: upstream defaults,
    # binary-cache hits instead of local compiles.
    programs.emacs = {
      enable = true;
      package = pkgs.emacs-pgtk;
    };
  };
}
