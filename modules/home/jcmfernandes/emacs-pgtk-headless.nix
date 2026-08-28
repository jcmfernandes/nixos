_: {
  # Headless emacs-pgtk: it starts with no Wayland compositor running,
  # keeps running when one exits, and opens frames on whichever comes
  # next -- the pgtk daemon can therefore start at boot, before niri,
  # and outlive every session.  Two coordinated patches; the what and
  # why live in the patch headers.
  #
  # Exposed as a flake package (not inlined into homeModules.emacs) so
  # `nix build .#emacs-pgtk-headless` verifies a nixpkgs bump without a
  # deploy: check that `ldd .emacs-*-wrapped` resolves libgdk-3 to a store
  # path whose .so contains the patch's "Continuing without the Wayland
  # connection" marker string.
  perSystem = {pkgs, ...}: {
    # The patches are referenced as path literals on purpose: each is
    # copied to the store as a single file, so this package only rebuilds
    # when a patch changes -- "${self}/..." would make it depend on the
    # whole tree and rebuild emacs on every commit.
    packages.emacs-pgtk-headless = let
      gtk3' = pkgs.gtk3.overrideAttrs (old: {
        patches = (old.patches or []) ++ [./emacs/gtk3-recoverable-wayland-disconnect.patch];
      });
    in
      (pkgs.emacs-pgtk.override {
        gtk3 = gtk3';
        # Overriding gtk3 alone is not enough: wrapGAppsHook3 propagates
        # its own stock gtk3, whose -L wins at link time, leaving the
        # stock libgdk in the binary's RUNPATH.
        wrapGAppsHook3 = pkgs.wrapGAppsHook3.override {gtk3 = gtk3';};
      }).overrideAttrs (old: {
        patches = (old.patches or []) ++ [./emacs/pgtk-survive-compositor-exit.patch];
      });
  };
}
