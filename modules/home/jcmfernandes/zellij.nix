{
  flake.homeModules.zellij = {
    programs.zellij.enable = true;
    # Shipped verbatim from dotfiles2 (a KDL file; hm's settings option
    # would re-render it from Nix and risk drift). It mirrors the tmux
    # prefix model: C-Space, then one letter into a sticky mode.
    xdg.configFile."zellij/config.kdl".source = ./zellij/config.kdl;
  };
}
