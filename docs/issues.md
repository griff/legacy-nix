# Outstanding Issues

## Issue 1: proxy patches — coverage incomplete

**Affected versions:** All versions that do not yet have a `proxy/patches/<name>.patch`.

**Symptom:** The proxy variant for a given version passes through unchanged (no proxy patches
applied) when no patch file exists, rather than failing explicitly.

**Currently patched proxy versions:** `nix_2_3`, `nix_2_24`, `lix_2_91`, `lix_2_93`.

**Status:** Unknown which other versions need proxy patches and what those patches should
contain. Requires investigation of which versions support `remoteProgram`, `--process-ops`,
and `narFromPath` natively.
