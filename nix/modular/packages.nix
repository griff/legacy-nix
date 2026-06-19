{
  lib,
  pkgs,
  version,
  src
}:
let
  pkgsForNix = pkgs.extend (final: prev: {
    boehmgc = prev.boehmgc.override {
      enableLargeConfig = true;
      initialMarkStackSize = 1048576;
    };
  });

  nixComponents = lib.makeScope pkgsForNix.newScope (
    import ./packaging/components.nix {
      inherit lib src version;
      officialRelease = true;
      teams = [];
      pkgs = pkgsForNix;
    }
  );
in
nixComponents.overrideSource src
