{ self, inputs, ... }: {

  flake.nixosConfigurations.moon = inputs.nixos-raspberrypi.lib.nixosInstaller {
    specialArgs = inputs;
    modules = [
      self.nixosModules.moonConfiguration
    ];
  };

}
