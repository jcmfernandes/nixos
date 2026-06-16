{ ... }: {
  flake.nixosModules.yubikey = { pkgs, ... }: {
    # PIV authentication key (slot 9a) -> SSH via yubikey-agent. The module
    # auto-enables services.pcscd (PIV is a smartcard/CCID applet) and only
    # creates the agent user service when a pinentry is set below.
    services.yubikey-agent.enable = true;

    # Required: the yubikey-agent user service is gated on this option, and
    # uses it as the PIN prompt. pinentry-qt is Wayland-native (renders under
    # niri without Xwayland), supports the secure `no-global-grab`, and avoids
    # the extra layers/failure modes the pinentry manual flags for gnome3.
    programs.gnupg.agent.pinentryPackage = pkgs.pinentry-qt;

    services.udev.packages = [ pkgs.yubikey-personalization ];

    # libykcs11.so (PKCS#11) for the git-signing wrapper (PIV slot 9c) plus
    # PIV/management tooling. Exposed via a stable env var so ~/.ssh/yk-ssh-keygen
    # needn't hardcode a /nix/store path.
    environment.systemPackages = [ pkgs.yubico-piv-tool pkgs.yubikey-manager ];
    environment.sessionVariables.YKCS11_MODULE = "${pkgs.yubico-piv-tool}/lib/libykcs11.so";
  };
}
