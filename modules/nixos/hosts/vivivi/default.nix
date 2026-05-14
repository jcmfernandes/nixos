{ self, inputs, ... }: {

  flake.nixosConfigurations.vivivi = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = inputs;
    modules = [
      self.nixosModules.viviviConfiguration
    ];
  };

}
