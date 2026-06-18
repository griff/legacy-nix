{pkgs, ...}:
{
  lix_2_90 = {
    version = "2.90.0";
  };
  lix_2_91 = pkgs.lix.overrideAttrs {
    version = "2.91.3";
    patches = [
      # Support for lowdown >= 1.4, https://gerrit.lix.systems/c/lix/+/3731
      (fetchpatch2 {
        name = "lix-2.91-lowdown-1.4.0.patch";
        url = "https://git.lix.systems/lix-project/lix/commit/ecff59d77371b21fef229c33ebb629bc49a8fad5.patch";
        sha256 = "sha256-2M5oId5kObwzpw67rddAPI2RbWPEVlGBrMUXZWqqmEo=";
      })
    ];
    doCheck = false;
    doInstallCheck = false;
    meta.broken = true;
    meta.flake.exported = "lix_2_91";
  };
  lix_2_92 = {
    version = "2.92.3";
  };
  lix_2_93 = pkgs.lix.overrideAttrs (finalAttrs: previousAttrs: {
    version = "2.93.4";
    doCheck = false;
    doInstallCheck = false;
    meta.flake.exported = "lix_2_93";
  });
  lix_2_94 = {
    version = "2.94.2";
  };
  lix_2_95 = {
    version = "2.95.3";
  };
}
