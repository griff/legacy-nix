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

  # nix 2.24–2.30 use LOWDOWN_TERM_NOLINK which was removed in lowdown 3.0.0.
  # Patch it to use LOWDOWN_NORELLINK (the successor flag) at build time.
  patchedComponents = if lib.versionOlder version "2.31"
    then components.overrideScope (_final: prev: {
      nix-cmd = prev.nix-cmd.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace markdown.cc \
            --replace-fail 'LOWDOWN_TERM_NOLINK' 'LOWDOWN_NORELLINK'
        '';
      });
    })
    else components;
in
patchedComponents.nix-cli.overrideAttrs (old: {
  meta = old.meta // {
    flake = { exported = self_attribute_name; };
    inherit maintainers;
  };
})
