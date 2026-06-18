{ pkgs, ... }:
let
  lib = pkgs.lib;
  inherit (pkgs) fetchFromGitHub fetchFromGitea rustPlatform clangStdenv;

  # lix 2.90 uses boost coroutines; boehmgc needs the stack-limit fallback patch.
  # 2.91+ dropped boost coroutines, so the patch is not needed there.
  boehmgc-coroutines = (pkgs.boehmgc.override { enableLargeConfig = true; }).overrideAttrs (drv: {
    patches = (drv.patches or []) ++ [ ../nix/patches/boehmgc-coroutine-sp-fallback.patch ];
  });
  boehmgc-plain = pkgs.boehmgc.override { enableLargeConfig = true; };

  aws-sdk-cpp-lix = (pkgs.aws-sdk-cpp.override {
    apis = [ "s3" "transfer" ];
    customMemoryManagement = false;
  }).overrideAttrs { requiredSystemFeatures = []; };

  editline-lix = pkgs.editline.override {
    inherit (pkgs) ncurses;
    enableTermcap = true;
  };

  makeLix =
    { version
    , hash
    , srcFn ? fetchFromGitHub
    , cargoDepsHash ? null
    , docCargoDepsHash ? null
    , attr_name
    , patches ? []
    }:
    let
      before91 = lib.versionOlder version "2.91";
      before92 = lib.versionOlder version "2.92";
      before94 = lib.versionOlder version "2.94";
      src = srcFn { owner = "lix-project"; repo = "lix"; rev = version; hash = hash; };
      outerArgs = { inherit version src patches; }
        // lib.optionalAttrs before92 {
          docCargoDeps = rustPlatform.fetchCargoVendor {
            name = "lix-doc-${version}";
            inherit src;
            sourceRoot = "${src.name or src}/lix-doc";
            hash = docCargoDepsHash;
          };
        }
        // lib.optionalAttrs (!before92) {
          cargoDeps = rustPlatform.fetchCargoVendor {
            name = "lix-${version}";
            inherit src;
            hash = cargoDepsHash;
          };
        };
    in
    (pkgs.callPackage (pkgs.callPackage ./common-lix.nix outerArgs) {
      stdenv = if before92 then pkgs.stdenv else clangStdenv;
      boehmgc = if before91 then boehmgc-coroutines else boehmgc-plain;
      aws-sdk-cpp = aws-sdk-cpp-lix;
      editline = editline-lix;
      enableDocumentation = false;
      confDir = "/etc";
      stateDir = "/nix/var";
      storeDir = "/nix/store";
    }).overrideAttrs (old: {
      doCheck = false;
      doInstallCheck = false;
      patches = (old.patches or [])
        ++ lib.optionals before92 [ ./patches/lowdown-opts.patch ]
        ++ lib.optionals (!before92 && before94) [ ./patches/lowdown-opts-lix.patch ];
      meta = old.meta // { flake.exported = attr_name; };
    });
in
{
  lix_2_90 = makeLix {
    version = "2.90.0";
    hash = "sha256-f8k+BezKdJfmE+k7zgBJiohtS3VkkriycdXYsKOm3sc=";
    docCargoDepsHash = "sha256-VPcrf78gfLlkTRrcbLkPgLOk0o6lsOJBm6HYLvavpNU=";
    attr_name = "lix_2_90";
  };

  lix_2_91 = makeLix {
    version = "2.91.3";
    hash = "sha256-b5d+HnPcyHz0ZJW1+LZl4qm4LGTB/TiaDFQVlVL2xpE=";
    docCargoDepsHash = "sha256-U820gvcbQIBaFr2OWPidfFIDXycDFGgXX1NpWDDqENs=";
    attr_name = "lix_2_91";
  };

  lix_2_92 = makeLix {
    version = "2.92.3";
    hash = "sha256-iP2iUDxA99RcgQyZROs7bQw8pqxa1vFudRqjAIHg9Iw=";
    cargoDepsHash = "sha256-YMyNOXdlx0I30SkcmdW/6DU0BYc3ZOa2FMJSKMkr7I8=";
    attr_name = "lix_2_92";
  };

  lix_2_93 = makeLix {
    version = "2.93.2";
    srcFn = args: fetchFromGitea ({ domain = "git.lix.systems"; } // args);
    hash = "sha256-J4ycLoXHPsoBoQtEXFCelL4xlq5pT8U9tNWNKm43+YI=";
    cargoDepsHash = "sha256-YMyNOXdlx0I30SkcmdW/6DU0BYc3ZOa2FMJSKMkr7I8=";
    attr_name = "lix_2_93";
  };

  lix_2_94 = makeLix {
    version = "2.94.2";
    srcFn = args: fetchFromGitea ({ domain = "git.lix.systems"; } // args);
    hash = "sha256-Nmqsl/YCnBW5U3TUfFWHGVUbyS2/Ll655BAE3qZilC4=";
    cargoDepsHash = "sha256-APm8m6SVEAO17BBCka13u85/87Bj+LePP7Y3zHA3Mpg=";
    attr_name = "lix_2_94";
  };

  lix_2_95 = makeLix {
    version = "2.95.2";
    srcFn = args: fetchFromGitea ({ domain = "git.lix.systems"; } // args);
    hash = "sha256-nFxJMIdcGTI9NiHAa5HZ2BmcGFLwC2pTq+V4Gjc499I=";
    cargoDepsHash = "sha256-a5XtutX+NS4wOqxeqbscWZMs99teKick5+cQfbCRGxQ=";
    attr_name = "lix_2_95";
  };
}
