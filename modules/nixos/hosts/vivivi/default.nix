{
  self,
  inputs,
  ...
}: {
  # vivivi rides stable, like the rest of the fleet. It was briefly pointed
  # at nixos-unstable (2026-05) but never deployed that way -- the machine
  # ran 26.05 throughout -- and following unstable cost a run of evaluation
  # breakages on moon, which had been pinned to vivivi's channel.
  #
  # The "build everything from source" policy is unaffected by this: it
  # exists because vivivi's kernel uses 16 KiB pages and trusts no binary
  # signing keys, which is an ABI and trust question, not a channel one.
  #
  # No `system =` arg: nixpkgs.hostPlatform is set inside
  # viviviConfiguration (and ideally moved to a hardware.nix sibling
  # module mirroring karma's layout).
  flake.nixosConfigurations.vivivi = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = inputs;
    modules = [
      self.nixosModules.viviviConfiguration
    ];
  };
}
