{
  description = "Legacy Nix versions";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nix-progress = {
      url = "github:griff/nix-progress";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-progress }: let
    inherit (nixpkgs) lib;
    systems = ["x86_64-linux" "x86_64-darwin"];
    forAllSystems = lib.genAttrs systems;
  in {
    packages = forAllSystems (system: 
      import ./packages.nix {
        inherit lib;
        pkgs = nixpkgs.legacyPackages.${system};
      });
    devShells = forAllSystems (system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
      default = pkgs.mkShell {
        name = "legacy-nix";
        buildInputs = with pkgs; [
          jujutsu
          nix-output-monitor
          nix-diff
          nix-progress.packages.${system}.default
        ];
      };
    });
  };
}
