{lib, pkgs, packages, ...}:
let
  patchDir = ./patches;

  makeProxy = n: v:
    if builtins.pathExists (patchDir + "/${n}.patch")
    then
      let patch = patchDir + "/${n}.patch";
      in
      if v ? passthru.appendPatches
      then v.passthru.appendPatches [patch]
      else v.overrideAttrs (drv: {
        patches = (drv.patches or []) ++ [patch];
      })
    else v;
in
lib.mapAttrs' (n: v: lib.nameValuePair "proxy_${n}" (makeProxy n v)) packages
