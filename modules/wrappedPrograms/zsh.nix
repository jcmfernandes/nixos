{
  lib,
  inputs,
  ...
}: {
  perSystem = {pkgs, ...}: {
    packages.myZsh = pkgs.lib.makeOverridable ({
      runtimeInputs ? [],
      editor ? "",
      interactiveInit ? "",
    }: let
      zshenv =
        pkgs.writeTextDir ".zshenv"
        # bash
        ''
          export PATH="${lib.makeBinPath runtimeInputs}:$PATH"
          ${lib.optionalString (editor != "") ''export EDITOR="${editor}"''}
          # Source user's own zshenv if it exists
          if [[ -f "$HOME/.zshenv" ]]; then
            source "$HOME/.zshenv"
          fi
        '';
      # Interactive-only init (tool activations etc.) belongs in .zshrc.
      zshrc = pkgs.writeTextDir ".zshrc" interactiveInit;
      zshConf = pkgs.symlinkJoin {
        name = "zsh-config";
        paths = [zshenv] ++ lib.optional (interactiveInit != "") zshrc;
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
