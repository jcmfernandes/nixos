{
  self,
  inputs,
  ...
}: {
  flake.nixosConfigurations.karma = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.karmaConfiguration
    ];
  };
}
