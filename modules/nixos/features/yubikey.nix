_: {
  flake.nixosModules.yubikey = {pkgs, ...}: {
    # PIV is a smartcard/CCID applet; pcscd is how PKCS#11 (and
    # age-plugin-yubikey) reach it. Previously auto-enabled by
    # services.yubikey-agent, which is gone -- SSH/signing now go through
    # the dedicated per-user PKCS#11 agent in homeModules.yubikey-ssh.
    services.pcscd.enable = true;

    services.udev.packages = [pkgs.yubikey-personalization];

    # PIV/management tooling. libykcs11.so ships in yubico-piv-tool and is
    # referenced by store path from homeModules.yubikey-ssh.
    environment.systemPackages = [pkgs.yubico-piv-tool pkgs.yubikey-manager];
  };
}
