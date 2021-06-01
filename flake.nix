{
  description = "Jaspers Nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-21.05";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-21.05-darwin";
    darwin.url = "github:LnL7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs-darwin";
    home-manager.url = "github:nix-community/home-manager/release-21.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    launch.url = "github:jwoudenberg/launch";
    launch.inputs.nixpkgs.follows = "nixpkgs";
    similar-sort.url =
      "git+https://git.bytes.zone/brian/similar-sort.git?ref=main";
    similar-sort.flake = false;
    nix-script.url = "github:BrianHicks/nix-script";
    nix-script.flake = false;
  };

  outputs = inputs: {

    overlays = {
      launch = final: prev: {
        jwlaunch = inputs.launch.defaultPackage."x86_64-linux";
      };
      nix-script = final: prev: {
        nix-script = prev.callPackage inputs.nix-script { };
      };
      pass = import ./overlays/pass.nix;
      random-colors = import ./overlays/random-colors.nix;
      similar-sort = final: prev: {
        similar-sort = prev.callPackage inputs.similar-sort { };
      };
      tabnine = import ./overlays/tabnine.nix;
      todo = import ./overlays/todo.nix;
    };

    nixosConfigurations.timid-lasagna = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        (import ./timid-lasagna/configuration.nix inputs)
        modules/desktop-hardware.nix
        inputs.home-manager.nixosModules.home-manager
      ];
    };

    nixosConfigurations.ai-banana = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ (import ./ai-banana/configuration.nix inputs) ];
    };

    darwinConfigurations.sentient-tshirt = inputs.darwin.lib.darwinSystem {
      modules = [
        (import ./sentient-tshirt/configuration.nix inputs)
        inputs.home-manager.darwinModules.home-manager
      ];
    };

  };
}
