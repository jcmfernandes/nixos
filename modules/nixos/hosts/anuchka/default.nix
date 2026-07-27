{
  self,
  inputs,
  ...
}: {
  flake.nixosConfigurations.anuchka = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.anuchkaConfiguration
    ];
  };
}
