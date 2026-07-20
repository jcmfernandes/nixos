{
  self,
  inputs,
  ...
}: {
  # vivivi rides nixos-unstable wholesale so the stdenv chain is internally
  # consistent under the "build everything from source" policy. Mixing
  # stable's stdenv with individual unstable packages trips
  # disallowedReferences and other closure-purity checks. moon stays on
  # stable.
  # No `system =` arg: nixpkgs.hostPlatform is set inside
  # viviviConfiguration (and ideally moved to a hardware.nix sibling
  # module mirroring karma's layout).
  flake.nixosConfigurations.vivivi = inputs.nixpkgs-unstable.lib.nixosSystem {
    specialArgs = inputs;
    modules = [
      self.nixosModules.viviviConfiguration
    ];
  };
}
