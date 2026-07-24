{
  flake.homeModules.emacs = {
    pkgs,
    lib,
    ...
  }: let
    # Plain Wayland-native emacs (emacs-pgtk), wrapped so straight.el's
    # runtime C compilation works on NixOS. Two packages in the config compile
    # native code on first use -- jinx (jinx-mod.c -> libenchant-2, found via
    # pkg-config) and tree-sitter grammars (treesit-install-language-grammar,
    # via cc/c++). NixOS has no /usr, so an unwrapped emacs can't find a
    # toolchain or enchant's pkg-config data. We give emacs' subprocesses just
    # those: a compiler (+pkg-config, git) on PATH and the .dev outputs of
    # enchant/glib on PKG_CONFIG_PATH. The nixpkgs cc-wrapper auto-embeds an
    # rpath into what it links, so the compiled modules find their libraries at
    # load time without any LD_LIBRARY_PATH (which would leak into every child
    # process emacs spawns).
    #
    # We deliberately do NOT use programs.emacs: it rebuilds its package through
    # emacsPackagesFor, which rejects a symlinkJoin-wrapped package. It only gave
    # us the binary + a .desktop anyway (config is stowed, no daemon), so we
    # deliver those directly via home.packages + xdg.desktopEntries below.
    emacs = pkgs.symlinkJoin {
      name = "emacs-native-build";
      paths = [pkgs.emacs-pgtk];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram $out/bin/emacs \
          --prefix PATH : ${lib.makeBinPath (with pkgs; [gcc binutils gnumake pkg-config git])} \
          --suffix PKG_CONFIG_PATH : ${lib.makeSearchPathOutput "dev" "lib/pkgconfig" (with pkgs; [enchant glib])}
      '';
    };
  in {
    home.packages = [emacs];

    # Replaces the .desktop that programs.emacs generated, pointing the GUI
    # app-launcher entry at the wrapped emacs.
    xdg.desktopEntries.emacs = {
      name = "Emacs";
      genericName = "Text Editor";
      exec = "emacs %F";
      icon = "emacs";
      categories = ["Development" "TextEditor"];
      terminal = false;
    };
  };
}
