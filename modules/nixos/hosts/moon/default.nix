{
  self,
  inputs,
  ...
}: {
  # nixos-raspberrypi's README ("Options for advanced usage") documents
  # constructing the system with `nixpkgs.lib.nixosSystem` directly. Two
  # requirements beyond a standard nixosSystem call:
  #   1. `specialArgs` MUST include `nixos-raspberrypi` so the rpi5
  #      board modules can find the flake reference. We pass all of
  #      `inputs`, so this is covered.
  #   2. `inputs.nixos-raspberrypi.lib.inject-overlays` MUST be in the
  #      module list — this is what wires the rpi5 kernel + firmware
  #      overlays into nixpkgs. Without it you'd get a generic
  #      aarch64-linux kernel instead of the Pi 5 one.
  #
  # The `raspberry-pi-5.{base,page-size-16k,display-vc4}` modules are
  # already imported inside moonConfiguration, so we don't repeat them
  # here. Same with the optional `trusted-nix-caches` (the nixos-raspberrypi
  # cachix substituters used to live in flake.nix's nixConfig; if you
  # want them again, add `inputs.nixos-raspberrypi.nixosModules.trusted-nix-caches`
  # to this list).
  #
  # Using stable's nixosSystem. moon still follows the same channel as
  # vivivi for cache-hit alignment -- that part never changed, only which
  # channel. Stable is also what nixos-raspberrypi pins its own nixpkgs
  # to, so the Pi kernel package and the NixOS modules reading it are
  # built from the same release; straddling them is what produced the
  # 26.11 breakages. cache.nixos.org's signed binaries are still trusted
  # on moon, so this is not the "rebuild everything from source" mode used
  # on vivivi.
  # No `system =` arg: nixpkgs.hostPlatform is set by raspberry-pi-5.base
  # inside moonConfiguration, which is the modern convention.
  flake.nixosConfigurations.moon = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = {inherit (inputs) nixos-raspberrypi;};
    modules = [
      inputs.nixos-raspberrypi.lib.inject-overlays
      inputs.nixos-raspberrypi.nixosModules.trusted-nix-caches
      inputs.nixos-raspberrypi.nixosModules.nixpkgs-rpi
      self.nixosModules.moonConfiguration
    ];
  };
}
