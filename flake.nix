{
  description = "A NixOS module for Anubis.";
  inputs = {};
  outputs = {self, ...}: {
    nixosModules = {
      default = self.nixosModules.anubis;
      anubis = import ./nixos-module.nix;
    };
  };
}
