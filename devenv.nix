{ pkgs, ... }: {
  packages = with pkgs; [
    yubikey-manager # ykman
    sops
    age-plugin-yubikey
    ssh-to-age
    openssh # ssh-keygen for host-key generation
    nixos-anywhere
    nixos-rebuild
    attic-client
    gitleaks
  ];
}
