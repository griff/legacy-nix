{pkgs, ...}:
{
  lix_2_91 = pkgs.lix.overrideAttrs {
    patches = [
      # Support for lowdown >= 1.4, https://gerrit.lix.systems/c/lix/+/3731
      (fetchpatch2 {
        name = "lix-2.91-lowdown-1.4.0.patch";
        url = "https://git.lix.systems/lix-project/lix/commit/ecff59d77371b21fef229c33ebb629bc49a8fad5.patch";
        sha256 = "sha256-2M5oId5kObwzpw67rddAPI2RbWPEVlGBrMUXZWqqmEo=";
      })
      ./proxy-patches/lix-2_91.patch
    ];
    doCheck = false;
    doInstallCheck = false;
    meta.broken = true;
    meta.flake.exported = "lix_2_91";
  };

  lix_2_93 = pkgs.lix.overrideAttrs (finalAttrs: previousAttrs: {
    patches = [
      ./proxy-patches/lix-2_93.patch
    ] ++ previousAttrs.patches;
    doCheck = false;
    doInstallCheck = false;
    meta.flake.exported = "lix_2_93";
  });
}