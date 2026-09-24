{
  flake.nixosModules.base = {
    # Keys only, on every host. Both default to true in nixpkgs, which left
    # password login open over ssh wherever an account had a password --
    # including moon, whose port 22 is open on the home LAN. Console and
    # local logins go through PAM, not sshd, so an account password (e.g.
    # vivivi's OCI serial console) still works there.
    #
    # Plain assignments, not mkDefault: this is fleet policy, and a host
    # reopening it should have to say so with mkForce.
    services.openssh.settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
}
