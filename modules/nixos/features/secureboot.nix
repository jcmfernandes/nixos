{inputs, ...}: {
  flake.nixosModules.secureboot = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [inputs.lanzaboote.nixosModules.lanzaboote];

    config = lib.mkMerge [
      # STAGED (always): tooling + lanzaboote config present but OFF. While
      # boot.lanzaboote.enable is false, systemd-boot stays the active
      # bootloader and nothing about booting changes. sbctl is available so
      # keys can be generated before arming. See karma's README runbook.
      {
        environment.systemPackages = [pkgs.sbctl];
        boot.lanzaboote = {
          pkiBundle = "/var/lib/sbctl";
          enable = lib.mkDefault false;
        };
      }

      # ARMED: only when boot.lanzaboote.enable = true (set in karma's
      # configuration.nix as the deliberate, physically-attended cutover).
      (lib.mkIf config.boot.lanzaboote.enable {
        boot = {
          loader.systemd-boot.enable = lib.mkForce false;
          # systemd initrd is required for TPM2-backed LUKS unlock. It is
          # already the nixpkgs 26.05 default; set explicitly as a guard so
          # arming never silently loses TPM unlock if that default changes.
          initrd.systemd.enable = true;
          initrd.luks.devices.cryptroot.crypttabExtraOpts = ["tpm2-device=auto"];
        };
      })
    ];
  };
}
