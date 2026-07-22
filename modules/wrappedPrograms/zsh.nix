{
  lib,
  inputs,
  ...
}: {
  perSystem = {pkgs, ...}: {
    packages.myZsh = pkgs.lib.makeOverridable ({runtimeInputs ? []}: let
      zshenv =
        pkgs.writeTextDir ".zshenv"
        # bash
        ''
          export PATH="${lib.makeBinPath runtimeInputs}:$PATH"
          # Source user's own zshenv if it exists
          if [[ -f "$HOME/.zshenv" ]]; then
            source "$HOME/.zshenv"
          fi
        '';
      # Interactive-only init (tool activations etc.) lives in the user's own
      # ~/.zshrc -- on karma managed by homeModules.desktop-session.
      zshrc =
        pkgs.writeTextDir ".zshrc"
        # bash
        ''
          if [[ -f "$HOME/.zshrc" ]]; then
            source "$HOME/.zshrc"
          fi
        '';
      zshConf = pkgs.symlinkJoin {
        name = "zsh-config";
        paths = [zshenv zshrc];
      };
    in
      inputs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.zsh;
        env = {
          ZDOTDIR = "${zshConf}";
        };
      }) {};
  };
}
