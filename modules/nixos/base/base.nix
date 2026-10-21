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

      # Eight eMudhra intermediates have recoverable private keys:
      # https://emudhra.we-have-a-problem.com/
      # The site names the first two roots; the emSign C1/C3 roots are
      # eMudhra's too. Drop once a patched cacert lands.
      security.pki.caCertificateBlacklist = [
        "Comodo AAA Services root"
        "emSign ECC Root CA - G3"
        "emSign Root CA - C1"
        "emSign ECC Root CA - C3"
      ];
    };
  };
}
