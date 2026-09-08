_: {
  # Headless emacs-pgtk: it starts with no Wayland compositor running,
  # keeps running when one exits, and opens frames on whichever comes
  # next -- the pgtk daemon can therefore start at boot, before niri,
  # and outlive every session.
  #
  # The package, its two patches and the reasoning behind them live in
  # their own flake: https://github.com/jcmfernandes/emacs-pgtk-headless.nix
  # That repo's CI builds it and asserts both patches survived into the
  # binary, so a bump is verified before it ever reaches this flake.
  #
  # Re-exported here so `nix build .#emacs-pgtk-headless` still works and
  # homeModules.emacs can keep reading it off `self.packages`.
  perSystem = {inputs', ...}: {
    packages.emacs-pgtk-headless = inputs'.emacs-pgtk-headless.packages.default;
  };
}
