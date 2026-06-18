{
  description = "Legacy Nix versions";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    inherit (nixpkgs) lib;
    systems = ["x86_64-linux" "x86_64-darwin"];
    forAllSystems = lib.genAttrs systems;
  in {
    packages = forAllSystems (system: let
        pkgs = nixpkgs.legacyPackages.${system};
        nix = (import ./nix { inherit pkgs self; });
        lix = (import ./lix { inherit pkgs self; });
        packages = lib.mapAttrs' (n: drv: lib.nameValuePair drv.meta.flake.exported drv) 
          (lib.filterAttrs (n: v: lib.isDerivation v) nix);
        proxyPackages = (import ./proxy { inherit pkgs lib self packages; });
      in packages // proxyPackages
    );
    devShells = forAllSystems (system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
      default = pkgs.mkShell {
        name = "legacy-nix";
        buildInputs = with pkgs; [
          jujutsu
          nix-output-monitor
        ];
      };
    });
  };
}
