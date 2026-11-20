{
  # OpenPGP with the subkeys on the YubiKeys' OpenPGP applet. Desktop-only:
  # the agent needs a display for the PIN prompt.
  flake.homeModules.gpg = {pkgs, ...}: {
    programs.gpg = {
      enable = true;
      # pcscd already owns the card for the PIV ssh-agent
      # (homeModules.yubikey-ssh). Go through it, not scdaemon's own CCID
      # driver, and share it instead of locking the other user out.
      scdaemonSettings = {
        disable-ccid = true;
        pcsc-shared = true;
      };
    };

    services.gpg-agent = {
      enable = true;
      # nixpkgs' gnupg points at a bin/pinentry it doesn't ship.
      pinentry.package = pkgs.pinentry-qt;
    };
  };
}
