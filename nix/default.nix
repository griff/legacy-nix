{ pkgs, ... }:
pkgs.callPackage (
{ lib
, config
, stdenv
, aws-sdk-cpp
, boehmgc
, libgit2
, callPackage
, fetchFromGitHub
, fetchpatch
, fetchpatch2
, runCommand
, buildPackages
, storeDir ? "/nix/store"
, stateDir ? "/nix/var"
, confDir ? "/etc"
}:
let
  boehmgc-nix_2_3 = boehmgc.override { enableLargeConfig = true; };

  boehmgc-nix = boehmgc-nix_2_3.overrideAttrs (drv: {
    patches = (drv.patches or [ ]) ++ [
      # Part of the GC solution in https://github.com/NixOS/nix/pull/4944
      ./patches/boehmgc-coroutine-sp-fallback.patch
    ];
  });

  aws-sdk-cpp-nix = (aws-sdk-cpp.override {
    apis = [ "s3" "transfer" ];
    customMemoryManagement = false;
  }).overrideAttrs {
    # only a stripped down version is build which takes a lot less resources to build
    requiredSystemFeatures = [ ];
  };

  libgit2-thin-packfile = libgit2.overrideAttrs (args: {
    nativeBuildInputs = args.nativeBuildInputs or []
      # gitMinimal does not build on Windows. See packbuilder patch.
      ++ lib.optionals (!stdenv.hostPlatform.isWindows) [
        # Needed for `git apply`; see `prePatch`
        buildPackages.gitMinimal
      ];
    # Only `git apply` can handle git binary patches
    prePatch = args.prePatch or ""
      + lib.optionalString (!stdenv.hostPlatform.isWindows) ''
        patch() {
          git apply
        }
      '';
    # taken from https://github.com/NixOS/nix/tree/master/packaging/patches
    patches = (args.patches or []) ++ [
      ./patches/libgit2-mempack-thin-packfile.patch
    ] ++ lib.optionals (!stdenv.hostPlatform.isWindows) [
      ./patches/libgit2-packbuilder-callback-interruptible.patch
    ];
  });

  commonAutoconf = args:
    callPackage
      (import ./common-autoconf.nix ({ inherit lib fetchFromGitHub; } // args))
      ({
        inherit storeDir stateDir confDir;
        boehmgc = boehmgc-nix;
        aws-sdk-cpp = aws-sdk-cpp-nix;
      } // lib.optionalAttrs (!lib.versionAtLeast args.version "2.12pre") {
        # aws-sdk-cpp 1.9.294 does not build with modern CMake (>=4.x);
        # disable AWS S3 store support for these old versions
        withAWS = false;
      });
  commonMeson =
    args:
    callPackage (import ./common-meson.nix ({ inherit lib fetchFromGitHub; } // args)) {
      inherit
        storeDir
        stateDir
        confDir
        ;
      enableDocumentation = false;
    };

  modular = { version, hash, self_attribute_name, patches ? [] }: let
    components = (pkgs.callPackage ./modular/packages.nix {
        inherit version;
        src = fetchFromGitHub {
          inherit hash;
          owner = "NixOS";
          repo = "nix";
          tag = version;
        };
      }).appendPatches patches;
    in components.nix-everything.overrideAttrs (old: {
      meta = old.meta // {
        flake.exported = self_attribute_name;
      };
    });

  # https://github.com/NixOS/nix/pull/7585
  patch-monitorfdhup = fetchpatch2 {
    name = "nix-7585-monitor-fd-hup.patch";
    url = "https://github.com/NixOS/nix/commit/1df3d62c769dc68c279e89f68fdd3723ed3bcb5a.patch";
    hash = "sha256-f+F0fUO+bqyPXjt+IXJtISVr589hdc3y+Cdrxznb+Nk=";
  };

  # Intentionally does not support overrideAttrs etc
  # Use only for tests that are about the package relation to `pkgs` and/or NixOS.
  addTestsShallowly = tests: pkg: pkg // {
    tests = pkg.tests // tests;
    # In case someone reads the wrong attribute
    passthru.tests = pkg.tests // tests;
  };

  addFallbackPathsCheck = pkg: addTestsShallowly
    { nix-fallback-paths =
        runCommand "test-nix-fallback-paths-version-equals-nix-stable" {
          paths = lib.concatStringsSep "\n" (builtins.attrValues (import ../../../../nixos/modules/installer/tools/nix-fallback-paths.nix));
        } ''
          # NOTE: name may contain cross compilation details between the pname
          #       and version this is permitted thanks to ([^-]*-)*
          if [[ "" != $(grep -vE 'nix-([^-]*-)*${lib.strings.replaceStrings ["."] ["\\."] pkg.version}$' <<< "$paths") ]]; then
            echo "nix-fallback-paths not up to date with nixVersions.stable (nix-${pkg.version})"
            echo "The following paths are not up to date:"
            grep -v 'nix-${pkg.version}$' <<< "$paths"
            echo
            echo "Fix it by running in nixpkgs:"
            echo
            echo "curl https://releases.nixos.org/nix/nix-${pkg.version}/fallback-paths.nix >nixos/modules/installer/tools/nix-fallback-paths.nix"
            echo
            exit 1
          else
            echo "nix-fallback-paths versions up to date"
            touch $out
          fi
        '';
    }
    pkg;
  
  teams = [
    lib.teams.nix
    lib.teams.security-review
  ];

  # Disables tests that have been flaky due to the darwin sandbox and fork safety
  # with missing shebangs.
  # See:
  # - https://github.com/NixOS/nix/pull/14778
  # - https://github.com/NixOS/nixpkgs/issues/476794
  # - https://github.com/NixOS/nix/issues/13106
  patches_common = lib.optional (
    stdenv.system == "aarch64-darwin"
  ) ./patches/skip-flaky-darwin-tests.patch;

  # Lowdown 3.0 compatibility patch for nix 2.31–2.33; fetched from the
  # upstream backport (same diff on every maintenance branch after
  # fetchpatch strips metadata).  Nix 2.34.4+ and the git snapshot
  # already include the fix in their tagged source.
  lowdown30Patch = pkgs.fetchpatch {
    name = "nix-lowdown-3.0-support.patch";
    url = "https://github.com/NixOS/nix/commit/472c35c561bd9e8db1465e0677f1efe2cb88c568.patch";
    hash = "sha256-ZCQgI/euBN8t9rgdCsGRgrcEWG3T5MUc+bQc4tIcHuI=";
  };

  # Lowdown 3.0 compatibility patch for nix 2.28 and 2.30, which have a
  # different markdown.cc layout (no LOWDOWN_TERM_NORELLINK branch) and
  # never received an upstream backport.
  lowdown30PatchOld = ./patches/lowdown-3.0-compat-2.28-2.30.patch;
in {
  nix_2_3 = ((commonAutoconf {
    version = "2.3.18";
    hash = "sha256-jBz2Ub65eFYG+aWgSI3AJYvLSghio77fWQiIW1svA9U=";
    patches = [
      patch-monitorfdhup
      ./patches/nix-2.3-boost-system.patch
    ];
    self_attribute_name = "nix_2_3";
  }).override { boehmgc = boehmgc-nix_2_3; }).overrideAttrs {
    # https://github.com/NixOS/nix/issues/10222
    # spurious test/add.sh failures
    enableParallelChecking = false;
  };

  nix_2_4 = commonAutoconf {
    version = "2.4";
    hash = "sha256-op48CCDgLHK0qV1Batz4Ln5FqBiRjlE6qHTiZgt3b6k=";
    # https://github.com/NixOS/nix/pull/5537
    patches = [
      ./patches/install-nlohmann_json-headers.patch
      ./patches/lowdown-opts-v1.patch
    ];
    self_attribute_name = "nix_2_4";
  };

  nix_2_5 = commonAutoconf {
    version = "2.5.1";
    hash = "sha256-GOsiqy9EaTwDn2PLZ4eFj1VkXcBUbqrqHehRE9GuGdU=";
    # https://github.com/NixOS/nix/pull/5536
    patches = [
      ./patches/install-nlohmann_json-headers.patch
      ./patches/lowdown-opts-v1.patch
    ];
    self_attribute_name = "nix_2_5";
  };

  nix_2_6 = commonAutoconf {
    version = "2.6.1";
    hash = "sha256-E9iQ7f+9Z6xFcUvvfksTEfn8LsDfzmwrcRBC//5B3V0=";
    patches = [
      ./patches/lowdown-opts-v1.patch
    ];
    self_attribute_name = "nix_2_6";
  };

  nix_2_7 = commonAutoconf {
    version = "2.7.0";
    hash = "sha256-m8tqCS6uHveDon5GSro5yZor9H+sHeh+v/veF1IGw24=";
    patches = [
      # remove when there's a 2.7.1 release
      # https://github.com/NixOS/nix/pull/6297
      # https://github.com/NixOS/nix/issues/6243
      # https://github.com/NixOS/nixpkgs/issues/163374
      (fetchpatch {
        url = "https://github.com/NixOS/nix/commit/c9afca59e87afe7d716101e6a75565b4f4b631f7.patch";
        sha256 = "sha256-xz7QnWVCI12lX1+K/Zr9UpB93b10t1HS9y/5n5FYf8Q=";
      })
      ./patches/lowdown-opts-v1.patch
    ];
    self_attribute_name = "nix_2_7";
  };

  nix_2_8 = commonAutoconf {
    version = "2.8.1";
    hash = "sha256-zldZ4SiwkISFXxrbY/UdwooIZ3Z/I6qKxtpc3zD0T/o=";
    patches = [
      ./patches/lowdown-opts-v1.patch
    ];
    self_attribute_name = "nix_2_8";
  };

  nix_2_9 = commonAutoconf {
    version = "2.9.2";
    hash = "sha256-uZCaBo9rdWRO/AlQMvVVjpAwzYijB2H5KKQqde6eHkg=";
    patches = [
      ./patches/lowdown-opts-v2.patch
    ];
    self_attribute_name = "nix_2_9";
  };

  nix_2_10 = commonAutoconf {
    version = "2.10.3";
    hash = "sha256-B9EyDUz/9tlcWwf24lwxCFmkxuPTVW7HFYvp0C4xGbc=";
    patches = [
      ./patches/flaky-tests.patch
      ./patches/lowdown-opts-v2.patch
    ];
    self_attribute_name = "nix_2_10";
  };

  nix_2_11 = commonAutoconf {
    version = "2.11.1";
    hash = "sha256-qCV65kw09AG+EkdchDPq7RoeBznX0Q6Qa4yzPqobdOk=";
    patches = [
      ./patches/flaky-tests.patch
      ./patches/lowdown-opts-v2.patch
    ];
    self_attribute_name = "nix_2_11";
  };

  nix_2_12 = commonAutoconf {
    version = "2.12.1";
    hash = "sha256-GmHKhq0uFtdOiJnuBwj2YwlZjvh6YTkfQZgeu4e0dLU=";
    patches = [
      ./patches/flaky-tests.patch
      ./patches/lowdown-opts-v3.patch
    ];
    self_attribute_name = "nix_2_12";
  };

  nix_2_13 = commonAutoconf {
    version = "2.13.6";
    hash = "sha256-pd2yGmHWn4njfbrSP6cMJx8qL+yeGieqcbLNICzcRFs=";
    patches = [
      ./patches/lowdown-opts-v3.patch
    ];
    self_attribute_name = "nix_2_13";
  };

  nix_2_14 = commonAutoconf {
    version = "2.14.1";
    hash = "sha256-5aCmGZbsFcLIckCDfvnPD4clGPQI7qYAqHYlttN/Wkg=";
    patches = [
      ./patches/lowdown-opts-v3.patch
      ./patches/libexpr-tests-rapidcheck-ldflags.patch
    ];
    self_attribute_name = "nix_2_14";
  };

  nix_2_15 = commonAutoconf {
    version = "2.15.3";
    hash = "sha256-sfFXbjC5iIdSAbctZIuFozxX0uux/KFBNr9oh33xINs=";
    patches = [
      ./patches/lowdown-opts-v3.patch
      ./patches/libexpr-tests-rapidcheck-ldflags.patch
    ];
    self_attribute_name = "nix_2_15";
  };

  nix_2_16 = commonAutoconf {
    version = "2.16.3";
    hash = "sha256-/tnjRCk+VaWPThzdn3C0zU1AMON+7AFsHgTTzErFxV4=";
    patches = [
      ./patches/lowdown-opts-v3.patch
    ];
    self_attribute_name = "nix_2_16";
  };

  nix_2_17 = commonAutoconf {
    version = "2.17.2";
    hash = "sha256-D5dgV4B7y5tD+nPU0Yus+R9nqgAelvm8imEeFzITLJA=";
    patches = [
      ./patches/lowdown-opts-v3.patch
    ];
    self_attribute_name = "nix_2_17";
  };

  nix_2_18 = commonAutoconf {
    version = "2.18.9";
    hash = "sha256-RrOFlDGmRXcVRV2p2HqHGqvzGNyWoD0Dado/BNlJ1SI=";
    patches = [
      ./patches/lowdown-opts-v3.patch
    ];
    self_attribute_name = "nix_2_18";
  };

  nix_2_19 = commonAutoconf {
    version = "2.19.7";
    hash = "sha256-CkT1SNwRYYQdN2X4cTt1WX3YZfKZFWf7O1YTEo1APfc=";
    patches = [
      ./patches/lowdown-opts-v3.patch
    ];
    self_attribute_name = "nix_2_19";
  };

  nix_2_20 = commonAutoconf {
    version = "2.20.9";
    hash = "sha256-b7smrbPLP/wcoBFCJ8j1UDNj0p4jiKT/6mNlDdlrOXA=";
    patches = [
      ./patches/lowdown-opts-v3.patch
    ];
    self_attribute_name = "nix_2_20";
  };

  nix_2_21 = commonAutoconf {
    version = "2.21.5";
    hash = "sha256-/+TLpd6hvYMJFoeJvVZ+bZzjwY/jP6CxJRGmwKcXbI0=";
    patches = [
      ./patches/lowdown-opts-v3.patch
    ];
    self_attribute_name = "nix_2_21";
  };

  nix_2_22 = commonAutoconf {
    version = "2.22.4";
    hash = "sha256-JWjJzMA+CeyImMgP2dhSBHQW4CS8wg7fc2zQ4WdKuBo=";
    patches = [
      ./patches/lowdown-opts-v3.patch
    ];
    self_attribute_name = "nix_2_22";
  };

  nix_2_23 = commonAutoconf {
    version = "2.23.4";
    hash = "sha256-rugH4TUicHEdVfy3UuAobFIutqbuVco8Yg/z81g7clE=";
    patches = [
      ./patches/lowdown-opts-v3.patch
    ];
    self_attribute_name = "nix_2_23";
  };

  nix_2_24 = commonAutoconf {
    version = "2.24.15";
    hash = "sha256-GHqFHLxvRID2IEPUwIfRMp8epYQMFcvG9ogLzfWRbPc=";
    patches = [
      ./patches/lowdown-opts-v4.patch
    ];
    self_attribute_name = "nix_2_24";
  };

  nix_2_25 = commonAutoconf {
    version = "2.25.5";
    hash = "sha256-9xrQhrqHCSqWsQveykZvG/ZMu0se66fUQw3xVSg6BpQ=";
    patches = [
      ./patches/lowdown-opts-v4.patch
    ];
    self_attribute_name = "nix_2_25";
  };

  nix_2_26 = commonMeson {
    version = "2.26.4";
    hash = "sha256-WmGMiwwC9RLomNtpDeRoe5bqBAH84A6pLcqi1MbcQi4=";
    self_attribute_name = "nix_2_26";
    patches = patches_common ++ [
      lowdown30PatchOld
    ];
  };

  nix_2_27 = commonMeson {
    version = "2.27.1";
    hash = "sha256-rBPulEBpn4IiqkPsetuh7BRzT2iGCzZYnogTAsbrvhU=";
    self_attribute_name = "nix_2_27";
    patches = patches_common ++ [
      lowdown30PatchOld
    ];
  };

  nix_2_28 = commonMeson {
    version = "2.28.7";
    hash = "sha256-Fq4+7uYz6bdE1HvPqn+qZcYX1rNilVKT7YAAPLA8170=";
    self_attribute_name = "nix_2_28";
    patches = patches_common ++ [
      lowdown30PatchOld
    ];
  };

  nix_2_29 = modular {
    version = "2.29.4";
    hash = "sha256-eVELGOeQg37AZLu7xnsaW9VA4fBr3x1d97I0iAoIt8A=";
    self_attribute_name = "nix_2_29";
    patches = patches_common ++ [
      lowdown30PatchOld
    ];
  };

  nix_2_30 = modular {
    version = "2.30.5";
    hash = "sha256-tGiV71RxtCNcUNX86ZwmOIghG4pLwm5nlRKd89er7Gk=";
    self_attribute_name = "nix_2_30";
    patches = patches_common ++ [
      lowdown30PatchOld
    ];
  };

  nix_2_31 = modular {
    version = "2.31.5";
    hash = "sha256-b7fhCXxl9qKTNPQvG8T/+nOxB95kalt9/aSY+ZSRctk=";
    self_attribute_name = "nix_2_31";
  };

  nix_2_32 = modular {
    version = "2.32.8";
    hash = "sha256-vj5o3dP9QaiW025a5INgg9j9XwScFsCYr6WrBxqSvUk=";
    self_attribute_name = "nix_2_32";
  };

  nix_2_33 = modular {
    version = "2.33.6";
    hash = "sha256-I3A0vFSFg3iI8tGBuQlAy7DzcxYcG39b06rfKOzGRvc=";
    self_attribute_name = "nix_2_33";
  };

  nix_2_34 = modular {
    version = "2.34.7";
    hash = "sha256-uj5KNW8Vdm60FCUxD2KsrCVH/WwoemvczWmmrb3Gvlo=";
    self_attribute_name = "nix_2_34";
  };
}) {}