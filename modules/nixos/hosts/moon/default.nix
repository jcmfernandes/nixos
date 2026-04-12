{ self, inputs, ... }: {

  flake.nixosConfigurations.moon = inputs.nixos-raspberrypi.lib.nixosInstaller {
    buildPlatform = "x86_64-linux";
    specialArgs = inputs;
    modules = [
      self.nixosModules.moonConfiguration
    ];
  };

}
