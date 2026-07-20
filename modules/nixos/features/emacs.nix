_: {
  flake.nixosModules.emacs = {pkgs, ...}: let
    # Latest stable Emacs (nixpkgs emacs-pgtk == 30.2, i.e. the emacs-30.2
    # release/tag), Wayland-native pure-GTK, with Protesilaos' emacs-git
    # configure flags. Overriding the flags busts the binary cache, so this
    # is compiled locally on karma.
    emacs =
      (pkgs.emacs-pgtk.override {
        # Prot's minimizing toggles. gif/tiff are already disabled in
        # nixpkgs; native-comp + tree-sitter are already default-on.
        # harfbuzz is always linked; json is built-in on Emacs 30.
        withGpm = false; # --without-gpm
        withSelinux = false; # --without-selinux
        withXinput2 = false; # --without-xinput2
        withCompressInstall = false; # --without-compress-install
        withCairo = true; # --with-cairo
      }).overrideAttrs (old: {
        configureFlags =
          (old.configureFlags or [])
          ++ [
            # nixpkgs only disables gif/tiff for the no-GUI variant; the pgtk
            # branch autodetects them from buildInputs, so disable explicitly.
            "--without-gif"
            "--without-tiff"
            "--with-sound=no"
            "--without-gsettings"
            "--without-gconf"
          ];
      });
  in {
    environment.systemPackages = [emacs];
  };
}
