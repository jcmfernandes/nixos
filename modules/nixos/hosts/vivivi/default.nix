{ self, inputs, ... }: {

  # vivivi rides nixos-unstable wholesale so the stdenv chain is internally
  # consistent under the "build everything from source" policy. Mixing
  # stable's stdenv with individual unstable packages trips
  # disallowedReferences and other closure-purity checks. moon stays on
  # stable.
  flake.nixosConfigurations.vivivi = inputs.nixpkgs-unstable.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = inputs;
    modules = [
      self.nixosModules.viviviConfiguration
    ];
  };

}
