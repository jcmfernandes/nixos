{
  flake.homeModules.tmux = {pkgs, ...}: {
    programs.tmux = {
      enable = true;
      # dotfiles2's .tmux.conf loaded these via TPM; hm delivers them from
      # nixpkgs instead (tmux-sensible via sensibleOnTop, which is the
      # default, stated here because the config relies on it).
      sensibleOnTop = true;
      plugins = with pkgs.tmuxPlugins; [
        yank
        open
      ];
      # Carried from dotfiles2 minus the TPM bootstrap; the reload bind
      # points at the hm-rendered path.
      extraConfig = builtins.readFile ./tmux/tmux.conf;
    };
  };
}
