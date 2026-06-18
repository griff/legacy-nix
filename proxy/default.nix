{lib, pkgs, packages, ...}:
lib.mapAttrs' (n: v: lib.nameValuePair "proxy_${n}" (v.overrideAttrs (drv: {
  patches = (drv.patches or []) ++ [
    (./patches + "/${n}.patch")
  ];
}))) packages