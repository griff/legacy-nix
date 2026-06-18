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
        mkPackages = attrs: lib.mapAttrs' (n: drv: lib.nameValuePair drv.meta.flake.exported drv)
          (lib.filterAttrs (n: v: lib.isDerivation v) attrs);
        nix-packages = mkPackages nix;
        lix-packages = mkPackages lix;
        packages = nix-packages // lix-packages;
        proxyPackages = (import ./proxy { inherit pkgs lib self packages; });
        all-packages = packages // proxyPackages;

        selected = [ "nix_2_3" "nix_2_24" "lix_2_93"];
        selected-nix = lib.getAttrs selected all-packages;

        isUnbroken = drv: (lib.isDerivation drv) && !(drv.meta.broken or false);
        filterBroken = attrs: lib.filterAttrs (n: v: isUnbroken v) attrs;

        mkAllNix = name: args: nixes: pkgs.runCommand "all-nix-${name}" args ''
          mkdir $out
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: d: ''
            ln -s ${toString d} $out/${n}
          '') (filterBroken nixes))}
        '';
      in all-packages // {
        all-nix = mkAllNix "nix" {} nix-packages;
        all-lix = mkAllNix "lix" {} lix-packages;
        all-proxy = mkAllNix "proxy" {} proxyPackages;
        all-no-proxy = mkAllNix "complete-no-proxy" {} packages;
        all = mkAllNix "complete" {} all-packages;
      }
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
