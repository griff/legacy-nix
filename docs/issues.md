# Outstanding Issues

## Issue 1: nix_2_26, nix_2_27 — nlohmann/json 3.11+ incompatibility

**Affected versions:** nix 2.26.4, nix 2.27.1 (built via `commonMeson`)

**Symptom:** Two unit test suites fail:
- `libutil-tests:nix-util-tests` — FAIL
- `libstore-tests:nix-store-tests` — FAIL

**Root cause:** nlohmann/json 3.11+ stores non-negative integer literals as
`number_unsigned_t` instead of `number_integer_t`. The `getInteger()` function in
`src/libutil/json-utils.cc` (and `.hh`) uses
`ensureType(value, value_t::number_integer).get_ref<const number_integer_t &>()`, which fails
to match values now stored as unsigned. This breaks deserialization of `narSize`,
`registrationTime`, and `fileSize` fields in path-info/nar-info JSON.

**Fix introduced in:** nix 2.28, via a new `getUnsigned()` function and a template
`getInteger<T>()` that tries both unsigned and signed storage via `get_ptr<T*>()`.

**Patch available:** `nix/patches/nlohmann-json-getinteger-2.26-2.27.patch`
Verified against both nix 2.26 and 2.27 sources with `patch --dry-run -p1`.

**Status:** Patch exists but is **not yet applied** in `nix/default.nix`.

---

## Issue 2: nix_2_26, nix_2_27 — toml11 3.7 timestamp separator

**Affected versions:** nix 2.26.4, nix 2.27.1 (built via `commonMeson`)

**Symptom:** One functional test fails:
- `lang:eval-okay-fromTOML-timestamps` — FAIL

**Root cause:** The TOML spec allows either `T` or a space as the separator between the date
and time parts of a datetime value. The test input (`eval-okay-fromTOML-timestamps.nix`)
contains `odt4 = 1979-05-27 07:32:00Z` (space separator). Older toml11 normalised this to `T`
in output; toml11 3.7 (in our nixpkgs) preserves the original space. The expected output file
(`eval-okay-fromTOML-timestamps.exp`) was written against the older behaviour and still expects
`"value": "1979-05-27T07:32:00Z"` for `odt4`, but the actual output is
`"value": "1979-05-27 07:32:00Z"`.

**Patch available:** `nix/patches/toml11-timestamps-2.26-2.27.patch`
Updates the single-line `.exp` file to use a space separator for `odt4`.

**Status:** Patch exists but is **not yet applied** in `nix/default.nix`.

---

## Issue 3: nix_2_29, nix_2_30 — `+N` version suffix causes 7 functional test failures on macOS

**Affected versions:** nix 2.29.4, nix 2.30.5 (built via `modular`)

**Symptom:** 7 functional test failures on macOS (5 distinct test scripts, 2 run in both
`main` and `ca` test suites):

| Test | File:Line | Failure mechanism |
|---|---|---|
| `user-envs` | `user-envs-test-case.sh:21` | `jq (.outputs.out \| test("$NIX_STORE_DIR.*"))` — `$NIX_STORE_DIR` used as jq ERE; `4+` in `2.29.4+1` treated as "one or more 4s" |
| `nix-shell` ×2 | `nix-shell.sh:38` | `[[ "$output" =~ ${testTmpDir}.* ]]` — `testTmpDir=$(pwd)/nix-shell` contains build dir path; `+` treated as ERE quantifier |
| `repl` ×2 | `repl.sh:37` | `grep -o -E "$NIX_STORE_DIR/\w*-simple"` — same `$NIX_STORE_DIR` ERE issue |
| `nix-profile` | `nix-profile.sh:199` | `diff` vs heredoc with `path:${flake2Dir}` — nix URL-encodes `+` as `%2B` in `path:` references, heredoc has literal `+` |
| `dubious-query` | `dubious-query.sh:20` | `grepQuiet "git+file://$repoDir"` — nix URL-encodes `+` as `%2B` in `git+file:` references |

**Root cause (chain):**

1. `nix/modular/packaging/components.nix` (vendored from nix source) appends `+${toString n}`
   to the version of every component derivation when `n = length(patches) > 0`.
2. nix_2_29 and nix_2_30 require `lowdown30PatchOld` (lowdown 3.0 compatibility) applied via
   `appendPatches`, giving `n = 1` (x86_64) or `n = 2` (aarch64-darwin with `patches_common`).
3. The build directory for `nix-functional-tests` becomes e.g.
   `/nix/var/nix/builds/nix-build-nix-functional-tests-2.29.4+1.drv-0/`.
4. `TEST_ROOT` and `NIX_STORE_DIR` (the local test store) are rooted inside this directory,
   so `+1` propagates into every path the tests use.
5. Four tests use these paths directly as ERE patterns; two tests compare against paths that nix
   URL-encodes differently from the raw filesystem path.

**Why it doesn't affect nixpkgs CI:** On Linux the nix build sandbox hardcodes the build
directory to `/build/` regardless of the derivation name. On macOS there is no Linux sandbox,
so the full derivation-named path (including `+N`) is used.

**Why nix 2.31+ is unaffected:** nix 2.31.5 already includes the lowdown 3.0 fix in its
source; no patch is needed so `n = 0` and no suffix is added.

**Status:** No fix currently applied. Two patches were written and verified during development
but the approach was contested (see plans).

---

## Issue 4: nix_2_25 — unknown status

**Affected versions:** nix 2.25.5 (built via `commonAutoconf`)

**Symptom:** Unknown — has not been explicitly tested recently.

**Notes:** Uses the autoconf builder. Likely subject to the same lowdown opts patch as 2.24
(`lowdown-opts-v4.patch`). No known test failures, but no confirmed passing build either.

---

## Issue 5: proxy patches — coverage incomplete

**Affected versions:** All versions that do not yet have a `proxy/patches/<name>.patch`.

**Symptom:** The proxy variant for a given version passes through unchanged (no proxy patches
applied) when no patch file exists, rather than failing explicitly.

**Currently patched proxy versions:** `nix_2_3`, `nix_2_24`, `lix_2_91`, `lix_2_93`.

**Status:** Unknown which other versions need proxy patches and what those patches should
contain. Requires investigation of which versions support `remoteProgram`, `--process-ops`,
and `narFromPath` natively.
