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
      environment.systemPackages = with pkgs; [
        ghostty.terminfo
        lsof
        gcc
        git
        glib
        htop
      ];

      # Eight eMudhra intermediates have recoverable private keys:
      # https://emudhra.we-have-a-problem.com/
      # cacert 3.131.1 dropped the emSign roots; the blocklist build
      # fails on entries absent from the store, so only Comodo remains.
      security.pki.caCertificateBlacklist = [
        "Comodo AAA Services root"
      ];
    };
  };
}
