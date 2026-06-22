# Plans for Outstanding Issues

## Plan A: Proxy patch coverage (Issue 1)

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
