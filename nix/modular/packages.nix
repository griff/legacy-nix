{ lib, pkgs, version, src, self_attribute_name, maintainers ? [] }:
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

  components = nixComponents.overrideSource src;
in
components.nix-cli.overrideAttrs (old: {
  meta = old.meta // {
    flake = { exported = self_attribute_name; };
    inherit maintainers;
  };
})
