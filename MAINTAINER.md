# Maintainer's guide

How `lfric-env-isambard` works inside, and how to maintain it. For the end-user
walkthrough, see [`README.md`](README.md); for AI-agent orientation see
[`CLAUDE.md`](CLAUDE.md).

The repo turns pinned upstream sources into a prebuilt, `module`-loadable LFRic
Apps environment. It is a refactor of a single large `install.sh` driver into:
pinned **git submodules** for every source, **standalone patch scripts**
(`patches/*-patch.sh`), a thin set of **task scripts** (`scripts/`), an install
**`PREFIX`** outside the repo, and **pixi** as an optional Stage-1 Python +
task runner.

## Repository layout

```
scripts/                # Stage 1 + shared helpers
  common.sh             #   sourced by every script: sets PREFIX/WORKING_DIR/variant,
                        #   puts vendored spack on PATH + modulefiles on MODULEPATH
  lib.sh                #   the Stage-1 build PHASES as sourceable functions
                        #     (prepare / concretize / install / fetch / ...); the drivers compose these
  concretize.sh         #   solve only: lfric_prepare + lfric_concretize (cheap login-node check)
  build.sh              #   Stage 1 driver: prepare + concretize + install + modulefile
  build.sbatch          #   submit build.sh to a Grace compute node (config block on top)
  fetch.sh              #   optional login-node pre-fetch driver: clone submodules + `spack fetch`
                        #     all sources into $PREFIX/source-cache (build then runs offline)
  activate.sh           #   `module load lfric-env/<variant>` (pixi auto-activation)
  print-versions.sh     #   `pixi run activate`: report rose/cylc/psyclone
  gen-modulefile.sh     #   resolve per-build paths -> Lua data table modulefile
  lfric-env.lua         #   the modulefile LOGIC (consumes the data table)
  patch-all.sh / unpatch.sh
  stage-physics.sh      #   set physics + lfric_core submodules to dependencies.yaml refs
  setup-cylc.sh         #   opt-in: write ~/.cylc run dir + isambard3 platform
  xios-verification.sh  #   check migrated XIOS source matches the pinned commit
examples/lfric-atm/     # Stage 2 EXAMPLE: compile lfric_atm + run its example
  build.sh  build.sbatch  README.md
spack-env/              # Spack env TEMPLATES (tracked); build.sh instantiates under PREFIX
  common.yaml           #   shared config: repos, gcc@14.3.0 external, python
  cray/spack.yaml       #   variant: system cray-mpich + Cray HDF5/netCDF (default)
  spack/spack.yaml      #   variant: mpich + HDF5/netCDF from source
spack-repo/lfric-isambard/  # local package repo: lfric-apps-isambard bundle, xios, foxml
vendor/                 # pinned submodules
  spack/  spack-packages/                     # Spack + its builtin packages
  lfric_apps/  lfric_core/  mo-spack-packages/ #   Stage-1 LFRic sources + MO package repo
  physics/{casim,jules,socrates,ukca}/         #   Stage-2-only (lfric_atm science)
patches/                # one *-patch.sh per upstream patch (applied in sorted order)
logs/                   # sbatch stdout (.gitkeep tracked; *.out ignored)
$LFRIC_PREFIX/          # OUTSIDE the repo — all build output (see below)
```

## Build locations: `PREFIX` vs `WORKING_DIR`

Two explicit locations, set in `scripts/common.sh` and overridden by the sbatch
config blocks. No auto-probing — the previous build-stage filesystem probe was
removed in favour of the sbatch setting `LFRIC_WORKING_DIR` explicitly.

- **`PREFIX`** (`LFRIC_PREFIX`, default `$PROJECTDIR/$USER/opt/<sysname>-<machine>`):
  the **persistent** install — Spack install tree (`$PREFIX/opt`), the per-variant
  directory environment + its view (`$PREFIX/spack-env/<variant>/`), the generated
  modulefiles (`$PREFIX/modulefiles/`), the source/misc caches and the redirected
  Spack user config/cache (`$PREFIX/spack-{config,cache}`). It lives **outside the
  repo** so Stage 2 never depends on the repo's path: the build bakes absolute
  paths into the modulefile + RPATHs, so once built the repo can move or be deleted
  and `module load lfric-env/<variant>` still works. Stage 1 (the build) still needs
  the repo: the vendored Spack + package repos live here.
- **`WORKING_DIR`** (`LFRIC_WORKING_DIR`, default `$PREFIX/stage`): Spack's
  **transient** build/compile stage *only* (`config:build_stage`). It is
  metadata-heavy (autotools/libtool touch thousands of small files); on a busy
  Grace node the shared Lustre is so contended that the *install* phase can crawl
  (e.g. a single `ncurses`/`gettext` install taking tens of minutes). So the sbatch
  points it at node-local NVMe (`$LOCALDIR`, a real ~3.5 TB SSD on grace nodes). It
  is per-node + transient: a re-run on another node just re-stages, and the install
  tree on `$PREFIX` persists so completed packages are still skipped.

Both variants **share one install tree** (`$PREFIX/opt`): Spack's content-addressed
store builds the large MPI-independent subtree (python/rose/cylc/psyclone/…) once
and links both views to it; only the MPI-dependent subtree (mpi, hdf5, netcdf, yaxt,
xios, shumlib, lfric) is built per variant. So keep `PREFIX` variant-independent.

The build redirects `SPACK_USER_CONFIG_PATH`/`SPACK_USER_CACHE_PATH` under `PREFIX`
so it neither reads nor writes the user's global `~/.spack`.

## Activation: the two-part Lmod modulefile

The built environment is loaded through **Lmod**, so pixi is only needed to *build*
it. The modulefile is self-contained — it puts the Spack view + package prefixes on
`PATH`/`PYTHONPATH`/`SHUMLIB_ROOT`/`LD_LIBRARY_PATH`/`SPACK_ENV`/… with **no nested
`module load`** — so it is fast and works under `/bin/sh`. To stay auditable it is
split in two:

- **Logic** — [`scripts/lfric-env.lua`](scripts/lfric-env.lua): version-controlled
  Lua holding all the `setenv`/`prepend_path`/`pushenv` rules. `build` snapshots a
  byte-identical copy to `$PREFIX/modulefiles/lfric-env.lua` so loading is
  repo-independent.
- **Data** — `$PREFIX/modulefiles/lfric-env/<variant>.lua` (written per build by
  `gen-modulefile.sh`): a flat table of the per-build paths, ending in
  `assert(loadfile("…/lfric-env.lua"))(data)`. (Lmod's sandbox forbids `dofile()`
  but allows `loadfile()` + passing the table as an argument.)

`$PREFIX/modulefiles/lfric-env/.modulerc.lua` marks `cray` as the default variant.
Regenerate a modulefile without a full rebuild (e.g. after moving `$PREFIX`):
`bash scripts/gen-modulefile.sh` (cray; prefix `LFRIC_STACK=spack` for spack). For
the cray variant, run it with the Cray PE modules loaded so `CRAY_LD_LIBRARY_PATH`
is populated.

## Build phases (`scripts/lib.sh`)

Stage 1 is decomposed into discrete phases, defined as sourceable functions in
`scripts/lib.sh` and composed by three thin drivers:

| Driver | Phases (`lfric_*`) | Purpose |
|--------|--------------------|---------|
| `concretize.sh` | `prepare` → `concretize` | the dependency **solve** only — the cheap, login-node check |
| `build.sh` | `prepare` → `verify_xios` → `concretize` → `install` → `regenerate_view` → `gen_modulefile` → `smoke_test` | the full build |
| `fetch.sh` | `clone_missing_submodules` → `prepare` → `concretize` → `fetch` | login-node source pre-fetch |

`lfric_prepare` is the shared setup (validate variant, check Python + submodules,
apply patches, load the toolchain modules, bootstrap Spack, write `config.yaml`,
instantiate the env). Splitting it out this way means **concretize is a
first-class step**, not a `STOP_AFTER_CONCRETIZE` early-exit buried in the install
driver, and `build` + `fetch` provably run the *same* solve.

`lfric_concretize` is **idempotent**: it runs `spack concretize --fresh` (no `-f`),
which is a ~1 s no-op when `spack.lock` already matches the manifest and re-solves
only when the manifest changed. The manifest is regenerated byte-identically each
run, so this never spuriously re-solves. Set `FORCE_CONCRETIZE=1` to force a fresh
re-solve (the old `build.sh` always passed `-f`, so it re-solved ~20 s every run).
`--fresh` keeps the solve deterministic for this pinned env; the lock embeds no
`$PREFIX` paths, so the solve does not depend on the install prefix's contents.

## The Spack environment: templates instantiated under PREFIX

The tracked `spack-env/<variant>/spack.yaml` are **templates**. `build.sh`
generates the real directory environment at `$PREFIX/spack-env/<variant>/`,
rewriting the template's relative `include: ../common.yaml` to an absolute path
back into the repo (done literally in `awk` via `index()`/`substr()`, not `sed`, so
nothing in the path is interpreted). This way the env's generated `.spack-env/`
view + lockfile land outside the repo, while the shared, version-controlled
`common.yaml` (and its relative `repos:`) stay tracked in the repo. The manifest is
regenerated every build, so a template edit always takes effect.

`common.yaml` holds everything identical across variants: the package repos
(`lfric` local bundle → `metoffice` mo-spack-packages → vendored `builtin`, in that
precedence), the `gcc@14.3.0` external + per-language pins, and python settings.
Each variant's `spack.yaml` carries only what differs (the MPI + HDF5/netCDF
provider) plus the manifest-only `view:`/`specs:` keys (which cannot live in an
included scope).

## GCC 14.3.0

The compiler is declared as an explicit external in `common.yaml`
(`gcc@14.3.0` → `/usr/bin/{gcc,g++,gfortran}-14`) and pinned via per-language
`require`s, so the solve is deterministic and `build` does **not** run
`spack compiler find` (which would rewrite the manifest and could drift to a stray
gcc). Isambard 3 previously shipped a complete `gcc@12.3.0` toolchain (used by
earlier builds) but reduced it to C-only (no `g++`/`gfortran` 12.3); `gcc@14.3.0`
is now the only complete cray-native C/C++/Fortran toolchain. To target a different
gcc, edit the external + `require`s in `common.yaml`.

## The two variants

`lfric_concretize` (in `lib.sh`) asserts the concretized lock actually matches the
requested variant (grepping `spack.lock`), so a mis-resolved external or a leaking `PrgEnv` can never
silently produce the wrong stack. Both are validated end-to-end on a `grace` node.

### `cray` (default)
Uses the system **cray-mpich** (Cray PE, `PrgEnv-gnu`) plus the Cray **parallel
HDF5/netCDF** as externals (`buildable: false`). `build.sh` loads `PrgEnv-gnu`
(required — it puts cray-mpich/libfabric/cray-pmi on the module path and sets the
`CRAY_*` lib paths), `craype-arm-grace` (Neoverse-V2 target), and
`cray-hdf5-parallel` + `cray-netcdf-hdf5parallel`.

cray-mpich 9.1.0 is a `gnu/12.3` build, but its Fortran modules are *GFORTRAN module
version 15* — which `gcc@14.3.0` also emits — so `use mpi`/`use mpi_f08` compile
cleanly against it. Because the concretizer prunes an external's dependencies, the
`libfabric`/`pmi`/`pals` library directories are injected through the externals'
`extra_attributes.environment.prepend_path` so dependents link and run
(`libmpi_gnu.so` NEEDs `libfabric.so.1`, `libpmi*`, `libpals`). The HDF5/netCDF
module **versions must match** the external prefixes in `spack-env/cray/spack.yaml`.

### `spack`
Builds **mpich + HDF5/netCDF from source**, loading no Cray modules (the `gcc`
external is the always-present `/usr/bin/gcc-14`). HDF5, netCDF-c and netCDF-fortran
are pinned to the **same versions** the cray variant externalizes
(`1.14.3`/`4.9.2`/`4.6.1`, matching `+mpi` variants) so the downstream DAG
concretizes identically — the two stay apples-to-apples. It is the portable
fallback; from-source `mpich` will not use the Slingshot/`cxi` fabric unless built
with libfabric, so it is for correctness/CI/comparison rather than production.

The Stage-2 example compiles differently per variant (see `examples/lfric-atm/build.sh`):
`cray` uses the Cray `ftn`/`CC` wrappers (which auto-inject the Cray HDF5/netCDF
`-I/-L/-l`); `spack` uses the view's `mpif90`/`mpic++` (lfric_core maps these to its
gfortran/g++ flag sets via `fortran/mpif90.mk` / `cxx/mpic++.mk` — note it must be
`mpic++`, not mpich's `mpicxx` alias, for which there is no `cxx/mpicxx.mk`).

## Patches

Each patch is a standalone, idempotent `patches/<NN>-<target>-patch.sh`, applied in
sorted order by `patch-all.sh` (discovered dynamically). `build` re-applies them
automatically, so it is always self-contained.

- `10-/11-lfric_core-*` — Fortran/Make fixes in `vendor/lfric_core`.
- `20-/21-spack-packages-papi-*` — papi build fixes (no-ops at the pinned commit;
  kept as guards against a submodule bump).
- `22-spack-packages-gdbm-automake-patch.sh` — gdbm `automake` build fix.
- `30-lfric_apps-local-sources-patch.sh` — **reproducible/offline sources.** Rewrites
  `get_source()` in lfric_apps so the build stages the pinned `lfric_core` + physics
  submodules in place (symlink + sanity-check) instead of cloning/fetching at build
  time; a remote (`.git`) source now *raises* instead of silently fetching. So the
  lfric_atm compile is a pure function of the checked-out submodule SHAs.

Every remaining patch modifies files **inside a submodule**, so `unpatch.sh` reverts
them all by `git reset --hard && git clean -fd` on `lfric_core`, `lfric_apps`, and
`spack-packages`. The Met Office *package* definitions are no longer patched: the
old `simit-spack` repo needed ~40 patch scripts under Spack 1.0, but its successor
`mo-spack-packages` is Spack-1.0 native (`api: v2.0`) and the cylc/rose tools now
ship in the Spack builtin repo.

## Bumping pinned versions

The authoritative pins are the submodule gitlinks (`git submodule status`).

- **Spack / spack-packages / a Met Office repo:** `cd vendor/<sub>`, `git fetch`,
  `git checkout <ref>`, then `git add vendor/<sub> && git commit` in the superproject.
  Re-run a build and check the variant assertions still pass.
- **Science sources (physics + lfric_core):** bump the ref(s) in
  `vendor/lfric_apps/dependencies.yaml`, run `bash scripts/stage-physics.sh` (or
  `pixi run stage-physics`) to checkout each submodule to its ref, then
  `git add vendor/physics vendor/lfric_core && git commit`. This is the explicit,
  reviewable way to pull in new science — `local_build.py` no longer auto-clones
  (patch 30), so the build only reads what you stage.

Pinned commits at time of writing (snapshot — `git submodule status` is authoritative):

| Submodule | Commit | Note |
|-----------|--------|------|
| `vendor/spack` | `7ae1d68c` | develop, Spack 1.0.x |
| `vendor/spack-packages` | `7e330489` | builtin packages |
| `vendor/lfric_apps` | `b5aee0b1` | vn3.1.1-88 |
| `vendor/lfric_core` | `bf236737` | 2026.03.2-38 |
| `vendor/mo-spack-packages` | `5e8359e0` | the `metoffice` package repo |
| `vendor/physics/casim` | `b0a6e38f` | 2026.03.2 |
| `vendor/physics/jules` | `3647a429` | 2026.03.2-14 |
| `vendor/physics/socrates` | `fb97f50a` | 2026.03.2 |
| `vendor/physics/ukca` | `1cdb9c26` | 2026.03.2-5 |

## Memory / OOM

`node-js` (V8), `rust` (LLVM) and `xios` (`group_template_decl.cpp`) have
translation units that use several GB each; at high `-j` under a tight memory
allocation they get OOM-killed (`cc1plus: Killed signal`). Two defences:

1. **Request enough memory.** On grace, memory is a consumable resource
   (`CR_CORE_MEMORY`): `RealMemory 230400 MB / 144 cores = 1600 MB/core`. The sbatch
   scripts set `--mem-per-cpu=1600M` (a node's full per-core share, scaling with
   `--cpus-per-task`); 24 cores ⇒ 37.5 GiB. Slurm's *default* (~1 GiB/core) is too
   little. Do **not** use a flat `--mem` far above the core-share — that inflates the
   job footprint and delays scheduling. If a build still OOMs, raise
   `--cpus-per-task` (memory rises with it).
2. **`build.sh` installs the heavy packages first at a capped `-j`** (`HEAVY_PKGS`
   at `HEAVY_JOBS`, default 6) before the rest at `SPACK_JOBS`, so the hogs never
   compile at full width.

The build also installs `libxml2` first (some netcdf-c builds probe `xml2-config`)
and `yaxt` serially (a known parallel race).

## Maintainer-only overrides

Beyond the user-facing vars in the README:

| Variable | Default | Purpose |
|----------|---------|---------|
| `HEAVY_JOBS` | `6` | Make jobs for LLVM/V8-bundling packages (OOM cap). |
| `HEAVY_PKGS` | `node-js rust xios` | Memory-hungry packages pre-built first at `HEAVY_JOBS`. |
| `FORCE_CONCRETIZE` | `0` | Set `1` to force a fresh re-solve (`concretize -f --fresh`); otherwise the solve is a no-op when the lock already matches the manifest. |
| `RUN_XIOS_VERIFICATION` | `1` | Set `0` to skip the XIOS network check in `build`. |
| `FETCH_JOBS` | `4` | `scripts/fetch.sh`: concurrency cap (submodule `--jobs` + `submodule.fetchJobs`) for the login node's `ulimit -u`. |
| `PRGENV_MODULE` / `CRAYPE_TARGET` | `PrgEnv-gnu` / `craype-arm-grace` | _cray only_: Cray PE + CPU-target modules. |
| `HDF5_MODULE` / `NETCDF_MODULE` | `cray-hdf5-parallel/1.14.3.9` / `cray-netcdf-hdf5parallel/4.9.2.3` | _cray only_: must match the external prefixes in `cray/spack.yaml`. |
| `PSYCLONE_TRANSFORMATION` | `minimum` | Stage-2 example: PSyclone optimisation set. |

## Adding things

- **A new dependency variant:** add `spack-env/<name>/spack.yaml` (include
  `../common.yaml`; set the MPI/IO provider + the manifest-only `view:`/`specs:`);
  extend the `case "$LFRIC_STACK"` validation + solve assertions in `build.sh` and
  the variant branch in `examples/lfric-atm/build.sh`; add the per-variant lib
  handling in `gen-modulefile.sh`/`lfric-env.lua` if it needs system libs like cray.
- **A new science example:** copy `examples/lfric-atm/` and change the build target
  + which physics deps you stage. The environment-activation block is reusable —
  it is the contract between Stage 1 and Stage 2.

## Testing

- **Static:** `bash -n scripts/*.sh examples/lfric-atm/build.sh`; `shellcheck` if available.
- **Cheap (login node):** `LFRIC_STACK=cray bash scripts/concretize.sh`
  → `CONCRETIZE_OK`; repeat with `LFRIC_STACK=spack`. Validates the manifest
  instantiation + variant assertions without the multi-hour install. Concretization
  is single-process and fine on the login node. (Add `FORCE_CONCRETIZE=1` to force a
  fresh re-solve rather than reuse a current lock.)
- **Full (compute node) — the invariant:** the four cases must build:
  `sbatch scripts/build.sbatch` (+ `--export=ALL,LFRIC_STACK=spack`) → `BUILD_OK`,
  then `sbatch examples/lfric-atm/build.sbatch` (+ spack) → `LFRIC_ATM_OK`.
