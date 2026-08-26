_: {
  flake.homeModules.mise = {
    # mise's global config (~/.config/mise/config.toml). Only the config
    # lives here: the package, the MISE_*_COMPILE vars and the nix-ld
    # plumbing stay system-side (modules/nixos/features/mise.nix), and the
    # shell activation comes from oh-my-zsh's mise plugin
    # (homeModules.shell). Hence package = null and every shell
    # integration off -- this module writes a file and nothing else.
    programs.mise = {
      enable = true;
      package = null;
      enableBashIntegration = false;
      enableZshIntegration = false;
      enableFishIntegration = false;
      enableNushellIntegration = false;

      globalConfig.tools."go:github.com/git-town/git-town/v24" = "latest";
    };
  };
}
