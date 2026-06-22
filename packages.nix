{ lib
, pkgs
, ...
}: let
  nix = (import ./nix { inherit pkgs; });
  lix = (import ./lix { inherit pkgs; });
  mkPackages = attrs: lib.mapAttrs' (n: drv: lib.nameValuePair drv.meta.flake.exported drv)
    (lib.filterAttrs (n: v: lib.isDerivation v) attrs);
  nix-packages = mkPackages nix;
  lix-packages = mkPackages lix;
  packages = nix-packages // lix-packages;
  proxyPackages = (import ./proxy { inherit pkgs lib packages; });
  all-packages = packages // proxyPackages;

  selected = [ "nix_2_3" "nix_2_24" "nix_2_34" "lix_2_91" "lix_2_93"];
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