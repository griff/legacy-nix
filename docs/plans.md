# Plans for Outstanding Issues

## Plan A: nix_2_26 and nix_2_27 (Issues 1 & 2)

Both patches already exist and have been verified. The only work remaining is wiring them into
`nix/default.nix`.

**Steps:**

1. Add two patch path variables after `lowdown30PatchOld` in the `let` block of
   `nix/default.nix`:
   ```nix
   nlohmannFix = ./patches/nlohmann-json-getinteger-2.26-2.27.patch;
   tomlTimestampsFix = ./patches/toml11-timestamps-2.26-2.27.patch;
   ```

2. Append both to the patch lists for `nix_2_26` and `nix_2_27`:
   ```nix
   nix_2_26 = commonMeson {
     ...
     patches = patches_common ++ [ lowdown30PatchOld nlohmannFix tomlTimestampsFix ];
   };
   nix_2_27 = commonMeson {
     ...
     patches = patches_common ++ [ lowdown30PatchOld nlohmannFix tomlTimestampsFix ];
   };
   ```

3. Build and confirm all three test suites pass:
   ```
   nix build .#nix_2_26 --no-link --print-build-logs
   nix build .#nix_2_27 --no-link --print-build-logs
   ```

**Risk:** Low. Both patches apply cleanly and the build was confirmed to pass end-to-end
during development (before being reverted).

---

## Plan B: nix_2_29 and nix_2_30 (Issue 3)

This is the harder problem. Three approaches are viable; they differ in invasiveness.

### Option B1: Remove the `+N` suffix from vendored `components.nix` (recommended)

The `+N` version suffix mechanism is in our vendored copy of
`nix/modular/packaging/components.nix`. Change the version logic to always use the base version
regardless of patch count:

```nix
# In nix/modular/packaging/components.nix, around line 112–114:
# Change from:
version =
  let n = lib.length finalScope.patches;
  in if n == 0 then prevAttrs.version else prevAttrs.version + "+${toString n}";
# To:
version = prevAttrs.version;
```

This is a one-line change to our vendored file. It does not affect upstream nix; it only removes
a signal that was never designed to survive functional test execution on macOS. nixpkgs's own CI
never sees this problem because Linux sandbox hides it.

**Risk:** Low. The `+N` suffix exists to signal "this binary was patched" but nothing in this
repo consumes that signal. All version tracking is done via the `self_attribute_name` / `meta.flake.exported` field.

### Option B2: Pre-apply patches to source before calling `packages.nix`

Replace `.appendPatches patches` in the `modular` function with `pkgs.applyPatches` on the raw
source before it is passed to `packages.nix`. This means patches are already baked into the
source tree, so `finalScope.patches = []` and `n = 0`:

```nix
modular = { version, hash, self_attribute_name, patches ? [] }: let
  rawSrc = fetchFromGitHub {
    inherit hash; owner = "NixOS"; repo = "nix"; tag = version;
  };
  src = if patches == [] then rawSrc else pkgs.applyPatches {
    src = rawSrc; inherit patches;
  };
  components = pkgs.callPackage ./modular/packages.nix { inherit version src; };
in components.nix-everything.overrideAttrs (old: {
  meta = old.meta // { flake.exported = self_attribute_name; };
});
```

**Risk:** Medium. `applyPatches` creates a new derivation in the store for the patched source,
which is different from how upstream nix/nixpkgs works. It also means `passthru.appendPatches`
on the resulting package wouldn't work the expected way (the proxy mechanism uses
`appendPatches` for modular builds).

### Option B3: Upstream fix to the test scripts

File a bug or PR against NixOS/nix to escape ERE metacharacters when using filesystem paths as
regex patterns (e.g. use `grep -F` where possible, or `${testTmpDir//+/\\+}` in bash). This
is the "correct" long-term fix but does nothing for our builds in the short term.

**Recommendation:** Use **Option B1** for an immediate fix. It is the least invasive change, is
confined to our vendored file, and correctly addresses the macOS-specific nature of the failure
without changing the `modular` function's interface (which the proxy mechanism depends on via
`appendPatches`).

---

## Plan C: nix_2_25 (Issue 4)

**Steps:**

1. Build it and examine the log:
   ```
   nix build .#nix_2_25 --no-link --print-build-logs 2>&1 | grep FAIL
   ```
2. If it fails, apply the same investigative approach as used for other versions (find source
   in store, read failing test output from log).

No known issues anticipated, but it has not been verified recently.

---

## Plan D: Proxy patch coverage (Issue 5)

For each nix/lix version, determine whether it needs a proxy patch by checking whether it
already supports the three required features natively:

1. **`remoteProgram` in SSH store** — check `src/libstore/ssh-store.cc` for `remoteProgram`
   option handling with `localhost` special-casing.
2. **`--process-ops` argument** — check `src/nix-daemon/nix-daemon.cc` for
   `processOps`/`process-ops` argument handling.
3. **`narFromPath` instead of `dumpPath`** — check `src/nix-daemon/nix-daemon.cc` for
   `NarFromPath` operation implementation.

For versions that lack any of these, a proxy patch needs to be written and placed in
`proxy/patches/<attr_name>.patch`. The existing patches (`nix_2_3.patch`, `nix_2_24.patch`,
`lix_2_91.patch`, `lix_2_93.patch`) are good reference examples.

**Suggested investigation order:** Start with nix_2_34 (newest, most likely to have all
features natively) and work backwards to identify where each feature was introduced, then patch
all versions below that threshold.
