# lfric-env-isambard

A [pixi](https://pixi.sh)-driven, submodule-based, reproducible build of the
**LFRic Apps Spack environment** for **Isambard 3** (GCC 12.3).

This is a refactor of a single large `install.sh` driver into:

- **pixi** as the Python bootstrap *and* task runner,
- **git submodules** for every upstream source (Spack, the Spack package repo,
  and the Met Office repos), pinned to known-good commits,
- **standalone patch scripts** (`patches/*-patch.sh`) replacing the inline
  `sed`/`awk`/`perl`/heredoc patching that the driver used to do,
- a repo-local, git-ignored `working_dir/` for all heavy build output.

## Quickstart

```bash
pixi run submodule-init   # one-time: clone the pinned submodules (needs repo access)
pixi run build            # build the Spack environment (~2-4 h from scratch)
pixi run activate         # report rose / cylc / psyclone versions
```

After `build`, **every** `pixi run ...` (and `pixi shell`) auto-activates the
environment, so e.g. `pixi run rose --version` or `pixi run spack find` work
directly. Before the build, auto-activation is a no-op (so `build` can run).

Expected result after a complete build:

```
rose 2.5.1
cylc 8.6.2
PSyclone version: 3.2.2
```

## Tasks

| Task | What it does |
|------|--------------|
| `submodule-init` | Clone the pinned submodules under `vendor/`. Run once. |
| `patch` | Apply every `patches/*-patch.sh` (sorted, idempotent). |
| `unpatch` | Revert all patches by resetting the patched submodules. |
| `build` | Build the Spack environment (applies patches, concretizes, installs). |
| `build-lfric-atm` | Optionally compile `lfric_atm` + run its example (needs SSH to physics repos). |
| `activate` | Activate + print rose/cylc/psyclone versions. |
| `verify-xios` | Check the migrated XIOS source matches the pinned commit. |
| `clean` | Remove `working_dir/` (keeps submodules and patches). |

`pixi run spack ...` works because activation puts the vendored Spack on `PATH`
(`vendor/spack`). The Spack environment lives in `spack-env/` (the `spack.yaml`
is tracked; the generated `.spack-env/` view is git-ignored).

## Layout

```
pixi.toml                 # pixi project: deps, activation hook, tasks
spack-env/spack.yaml      # the tracked Spack environment definition
spack-repo/lfric-isambard # local "lfric-apps-isambard" bundle package repo
vendor/                   # submodules (pinned)
  spack/                  # spack/spack
  spack-packages/         # spack/spack-packages (Spack builtin packages)
  lfric_apps/             # MetOffice/lfric_apps
  lfric_core/             # MetOffice/lfric_core
  simit-spack/            # MetOffice/simit-spack
patches/                  # one *-patch.sh per upstream patch (sorted by prefix)
scripts/                  # common.sh, activate.sh, build.sh, build-lfric-atm.sh, ...
working_dir/              # git-ignored: Spack install tree, caches, env view, logs
```

## Pinned versions

| Submodule | Commit |
|-----------|--------|
| `vendor/spack` | `73eaea13` (Backports v1.0.0) |
| `vendor/spack-packages` | `18eacd03` |
| `vendor/lfric_apps` | `e906813e` (Release vn3.0) |
| `vendor/lfric_core` | `da8a9264` |
| `vendor/simit-spack` | `ece4c481` |

## Patches

Each patch is a standalone, idempotent `patches/<NN>-<target>-patch.sh`,
applied in sorted order by `patch-all.sh` (discovered dynamically — names are
not hardcoded):

- `10-lfric_core-*` — Fortran/Make fixes in `vendor/lfric_core`.
- `20-spack-packages-papi-*` — papi build fixes in `vendor/spack-packages`
  (no-ops at the pinned commit, kept as guards against a submodule bump).
- `30-simit-*` — (re)write `simit-spack` package definitions for Spack 1.0.
- `40-simit-spack-imports-patch.sh` — repo-wide API/import normalisation that
  must run after the per-package patches.

Because every patch modifies files **inside a submodule** (overwriting tracked
files or adding package directories), `pixi run unpatch` reverts them all by
`git reset --hard && git clean -fd` on `lfric_core`, `simit-spack`, and
`spack-packages`. `build` re-applies patches automatically, so it is always
self-contained.

## Notes / caveats

- **Build output location.** Everything heavy (~7.5 GB) goes under
  `working_dir/` next to the repo. The build redirects Spack's user config and
  cache there too (`SPACK_USER_CONFIG_PATH`, `SPACK_USER_CACHE_PATH`), so it
  neither reads nor writes your global `~/.spack`. Put the repo on a filesystem
  with space (e.g. `$SCRATCH`), or set `LFRIC_WORKING_DIR` to relocate output.
- **GCC 12.3.** `build` runs `module load gcc-native/12.3` (override with
  `GCC_MODULE`). Spack's `compiler find` must see `gcc@12.3.0`.
- **simit-spack SSH/SSO.** At time of writing, the SSH key on this machine is
  authorized for `lfric_apps`/`lfric_core` but **not** `simit-spack`
  (`MetOffice` SAML SSO rejects it), even though the account has pull access.
  If `submodule-init` fails on `simit-spack`, either authorize your SSH key for
  it (GitHub → Settings → SSH keys → Configure SSO), or switch that submodule to
  HTTPS with a credential helper (`gh auth setup-git`).
- **lfric_atm** is intentionally not part of `build`: it clones private physics
  repos (casim/jules/socrates) over SSH. The Spack environment is complete
  without it.

## Useful overrides

| Variable | Default | Purpose |
|----------|---------|---------|
| `SPACK_JOBS` | `8` | Parallel Spack make jobs (raise on a dedicated compute node; keep modest on a shared login node) |
| `HEAVY_JOBS` | `6` | Make jobs for LLVM/V8-bundling packages (`node-js`, `rust`); capped to avoid OOM (see below) |
| `HEAVY_PKGS` | `node-js rust` | Packages built first at `HEAVY_JOBS` before the rest |
| `MAKE_JOBS` | `8` | Parallel make jobs for `lfric_atm` |
| `LFRIC_WORKING_DIR` | `<repo>/working_dir` | Where build output lands |
| `GCC_MODULE` | `gcc-native/12.3` | Module providing `gcc@12.3.0` |
| `RUN_XIOS_VERIFICATION` | `1` | Set `0` to skip the XIOS network check in `build` |
| `CYLC_RUN_BASE` | `$PROJECTDIR/$USER/cylc-run` | Cylc run directory |

**Memory / OOM.** `node-js` (V8) and `rust` (LLVM) have translation units that use
several GB each; at high `-j` on a swapless or shared node they get OOM-killed
(`cc1plus: Killed signal`). `build` therefore installs the `HEAVY_PKGS` first at
`HEAVY_JOBS` (default 6) and the rest at `SPACK_JOBS`. On a busy login node use a
modest `SPACK_JOBS` (≤16); on a dedicated compute node with plenty of RAM you can
raise both.
