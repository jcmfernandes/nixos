{
  flake.nixosModules.base = {
    lib,
    pkgs,
    ...
  }: {
    options.preferences = {
      autostart = lib.mkOption {
        type = lib.types.listOf (lib.types.either lib.types.str lib.types.package);
        default = [];
      };
    };

    config = {
      # The admin machine's terminal is Ghostty; ssh forwards
      # TERM=xterm-ghostty, which the hosts cannot resolve without this
      # terminfo entry (zsh warns on login, TUIs fall back to dumb
      # rendering). The terminfo output alone lands in the closure, not
      # the ghostty runtime.
      environment.systemPackages = [pkgs.ghostty.terminfo];
    };
  };
}
