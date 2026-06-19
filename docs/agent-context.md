# legacy-nix: Agent Context

## Purpose

This repository builds every minor release of **Nix** (2.3–2.34) and **Lix** (2.90–2.95) as
self-contained, vendored Nix packages. The goal is compatibility testing — specifically, providing
old daemon binaries to act as proxies for testing the Nix daemon wire protocol across versions.

Each package is also wrapped in a "proxy" variant that applies extra patches enabling the binary to
function as a daemon proxy (see `proxy/README.md` for the three requirements: `remoteProgram`,
`--process-ops`, and no `dumpPath`).

The flake exposes packages for `x86_64-linux` and `x86_64-darwin`.

---

## Repository Layout

```
flake.nix             # Entry point. Delegates to packages.nix.
packages.nix          # Aggregates nix/, lix/, and proxy/ into one package set.
                      # Also exposes all-nix, all-lix, all-proxy, all convenience targets.

nix/
  default.nix         # All nix version definitions. Three builders:
                      #   commonAutoconf  — nix 2.3–2.25 (autoconf/make)
                      #   commonMeson     — nix 2.26–2.28 (meson, pre-modular)
                      #   modular         — nix 2.29+ (nix's own modular packaging)
  common-autoconf.nix # Vendored builder for autoconf-era nix
  common-meson.nix    # Vendored builder for meson-era nix
  modular/            # Vendored copy of nix's own packaging/components.nix infrastructure
  patches/            # All patches applied to nix sources

lix/
  default.nix         # All lix version definitions via makeLix helper
  common-lix.nix      # Vendored copy of nixpkgs common-lix.nix builder
  patches/            # Patches applied to lix sources (lowdown opts)

proxy/
  default.nix         # For each package, applies proxy/patches/<name>.patch if it exists.
                      # Uses appendPatches for modular builds, overrideAttrs otherwise.
  patches/            # Per-version proxy patches (nix_2_3, nix_2_24, lix_2_91, lix_2_93)
  README.md           # Explains the three requirements for proxy operation
```

---

## Tool Usage

This repo uses **jujutsu (`jj`)**, not plain git, for version control.

**Building packages:**
```
nix build .#nix_2_29          # build a specific version
nix build .#all-nix           # build all nix versions (symlinks in result/)
nix build .#all               # build everything including lix and proxy variants
```

**Checking build logs:**
```
nix log .#nix_2_26            # full build log for a package
```

**Evaluating without building:**
```
nix eval .#nix_2_29.meta.flake.exported   # sanity check evaluation
nix eval .#nix_2_29 --apply 'p: p.version' --raw
```

**Finding a package's source in the store:**
```
nix derivation show $(nix path-info --derivation .#nix_2_29) | python3 -c "
import json,sys; d=json.load(sys.stdin); print(list(d.values())[0]['env']['src'])"
```

---

## How Versions Are Built

### Autoconf era (nix 2.3–2.25) — `commonAutoconf`
Standard `mkDerivation` via `nix/common-autoconf.nix`. Patches are passed directly to the
derivation. Tests run as part of the build (`doCheck = true` inherited).

### Meson era (nix 2.26–2.28) — `commonMeson`
`mkDerivation` via `nix/common-meson.nix`. Patches passed directly. Documentation disabled
(`enableDocumentation = false`). Tests run unconditionally.

### Modular era (nix 2.29+) — `modular`
Uses nix's own `packaging/components.nix` infrastructure, vendored in `nix/modular/`. The
`modular` function calls `packages.nix` to get a scope, then calls `.appendPatches patches` on
it. The final package is `components.nix-everything`, which has `doCheck = true` and includes
both unit tests and functional tests as build-time gates.

**Important**: `components.nix` appends `+${n}` to the version of every component derivation
when `n = length(patches) > 0`. This causes the build directory to be named e.g.
`nix-functional-tests-2.29.4+1.drv-0/`, which is the root cause of macOS test failures
(see Issues).

### Lix (2.90–2.95) — `makeLix`
Uses vendored `common-lix.nix`. Tests are unconditionally disabled (`doCheck = false`,
`doInstallCheck = false`). Versions 2.90–2.91 use the standard stdenv; 2.92+ use clangStdenv.

---

## How to Investigate Build Failures

1. **Get the build log:**
   ```
   nix log .#nix_2_26
   ```
   Failures appear as `FAIL` lines. The `test failed at:` lines give the exact script and line
   number.

2. **Find the source in the store:**
   Use `nix derivation show` on the drv and extract the `src` env var. The source is a read-only
   store path — copy files to `/tmp` with `chmod -R u+w` before modifying them.

3. **Verify a patch applies:**
   ```
   patch --dry-run -p1 -d /path/to/source < nix/patches/my.patch
   ```
   Note: the store is read-only, so this only works on a writable copy.

4. **Check nixpkgs master for reference fixes:**
   ```
   curl -sL https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/tools/package-management/nix/default.nix
   ```
   Nixpkgs master is the upstream reference for how newer nixpkgs handles each version.

5. **Stage new files before building** (jujutsu tracks the working copy, but nix evaluates via
   git-compatible paths): new patch files must be `jj add`-ed or `git add`-ed before they can be
   referenced in a nix build.

---

## Key Constraints

- **Do not rely on `pkgs.lixPackageSets`** — our pinned nixpkgs removes lix 2.90–2.93 as `throw`.
  All lix versions are built from vendored source.
- **Builds must be self-contained** — no network access during builds, all sources fetched by hash.
- **Both Linux and macOS** (`x86_64-linux`, `x86_64-darwin`) are target platforms. Some test
  failures are macOS-specific due to the absence of the Linux nix sandbox.
