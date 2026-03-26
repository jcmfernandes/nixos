{
  lib,
  inputs,
  ...
}: {
  perSystem = {
    pkgs,
    ...
  }: {
    packages.myZsh = pkgs.lib.makeOverridable ({
      runtimeInputs ? [],
      editor ? "",
    }: let
      zshConf =
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
