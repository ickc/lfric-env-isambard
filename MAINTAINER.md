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
examples/minimal-compile/  # MINIMAL-COMPILE EXAMPLE: compile lfric_atm + run its example
  build.sh  build.sbatch  README.md
examples/science-suites/ # SCIENCE-SUITE EXAMPLES: run real Rose/Cylc LFRic suites
  run-suite.sh           #   launcher: cylc vip a suite against the built env
  site/activate-env.sh   #   ACTIVATE_ENV: module-load the env for suite tasks
  site/extract-sources.sh #  offline per-suite source extract (dependencies.yaml)
  u-dn704/ u-dr932/ u-dt000/  # adapted suites (dependencies.yaml + flow.cylc) + README
spack-env/              # Spack env TEMPLATES (tracked); build.sh instantiates under PREFIX
  common.yaml           #   shared config: repos, gcc@14.3.0 external, python
  cray/spack.yaml       #   variant: system cray-mpich + Cray HDF5/netCDF (default)
  spack/spack.yaml      #   variant: mpich + HDF5/netCDF from source
spack-repo/lfric-isambard/  # local package repo: lfric-apps-isambard bundle, xios, foxml
vendor/                 # pinned submodules
  spack/  spack-packages/                     # Spack + its builtin packages
  lfric_apps/  lfric_core/  mo-spack-packages/ #   LFRic sources (mirrors) + MO package repo
  physics/{casim,jules,socrates,ukca}/         #   LFRic physics sources (examples only)
patches/                # one *-patch.sh per upstream patch (applied in sorted order)
logs/                   # sbatch stdout (.gitkeep tracked; *.out ignored)
$LFRIC_PREFIX/          # OUTSIDE the repo — all build output (see below)
```

## Build locations: `BASE` / `PREFIX` / `WORKING_DIR` (and the env version)

Locations are set in `scripts/common.sh` and overridden by the sbatch config
blocks. No auto-probing — the previous build-stage filesystem probe was removed in
favour of the sbatch setting `LFRIC_WORKING_DIR` explicitly.

The install tree is **versioned** by `LFRIC_ENV_VERSION` (CalVer, e.g.
`v2026.06.30`), read from the committed `./VERSION` file (a plain file read, not
inference; overridable via the env var). The point is discipline: many commits do
not change Stage 1, so the version is bumped *deliberately* (`scripts/bump-env-
version.sh` / `pixi run bump-env-version` writes `v$(date +%Y.%m.%d)`), and a
rebuild then lands in a fresh prefix instead of silently overwriting an environment
others are already loading. It is the **environment's** version — deliberately
distinct from any LFRic apps/core version.

- **`BASE`** (`LFRIC_PREFIX`, default `$PROJECTDIR/$USER/opt/<sysname>-<machine>`):
  the per-arch container, **shared across env versions**. Holds the version-
  independent bits: the shared **modulefiles** tree (`$BASE/modulefiles/`) and the
  content-addressed download caches (`$BASE/source-cache`, `$BASE/misc-cache`, i.e.
  `LFRIC_SOURCE_CACHE`/`LFRIC_MISC_CACHE`). Sharing the download caches lets a new
  version reuse already-downloaded sources instead of re-fetching (and avoids re-
  hitting the flaky `gitlab.in2p3.fr` XIOS host). Setting `LFRIC_PREFIX` overrides
  `BASE`; versioning still applies underneath it.
- **`PREFIX`** = `$BASE/$LFRIC_ENV_VERSION`: the **persistent, per-version** install
  — Spack install tree (`$PREFIX/opt`), the per-variant directory environment + its
  view (`$PREFIX/spack-env/<variant>/`), and the redirected Spack user config/cache
  (`$PREFIX/spack-{config,cache}`). It lives **outside the repo** so the examples
  never depend on the repo's path: the build bakes absolute paths into the modulefile
  + RPATHs, so once built the repo can move or be deleted and `module load
  lfric-env/<version>/<variant>` still works. Stage 1 (the build) still needs the
  repo: the vendored Spack + package repos live here.
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

**Modulefiles + discoverability.** The generated modulefiles are written to the
shared `$BASE/modulefiles/` tree keyed `lfric-env/<version>/<variant>` (e.g.
`lfric-env/v2026.06.30/cray.lua`), with the committed logic snapshot at
`$BASE/modulefiles/lfric-env.lua`. So a single `module use $BASE/modulefiles`
makes `module avail lfric-env` list every built version × variant at once. Default
selectors (`.modulerc.lua`, rewritten each build): within a version `cray` is the
default variant, and a bare `module load lfric-env` resolves to the most recently
built version's `cray`. `scripts/gen-modulefile.sh` writes all of this; it is
standalone-runnable, so the selectors can be refreshed without a rebuild.

## Activation: the two-part Lmod modulefile

The built environment is loaded through **Lmod**, so pixi is only needed to *build*
it. A single `module load lfric-env/<version>/<variant>` is the **whole contract**
for compiling or running against the env: it puts the Spack view + package prefixes
on `PATH`/`PYTHONPATH`/`SHUMLIB_ROOT`/`LD_LIBRARY_PATH`/`SPACK_ENV`/…, sets the
compile toolchain (`FC`/`CXX`/`LDMPI` + view-wide `FFLAGS`/`LDFLAGS`), and — for the
`cray` variant — `load()`s the Cray PE modules it needs (`PrgEnv-gnu` + Cray HDF5/
netCDF). Those Cray `load()`s are the **one** exception to "no nested `module
load`": Lmod resolves module hierarchy by statically scanning the *top-level*
generated modulefile for `load(...)`, so they must be emitted there by
`gen-modulefile.sh`, not inside the `loadfile()`d logic (where a `load()` is
silently a no-op — `try_load()` is unaffected). The `spack` variant needs none: its
MPI/HDF5/netCDF are from-source in the view. Either way it works under `/bin/sh`. To
stay auditable it is split in two:

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

**The examples consume exactly this contract and nothing more.** Both the
minimal-compile example (`examples/minimal-compile/build.sh`) and the science-suite
examples (`examples/science-suites/site/activate-env.sh` + each `u-*/flow.cylc`,
which do `FC = $FC`) are **integration tests**: they load the module the way an end
user would and rely on it for the whole toolchain, rather than hand-rolling the Cray
module loads / `FC`-`CXX`-`LDMPI` / `FFLAGS`-`LDFLAGS` themselves (they used to —
that duplicated, and could drift from, what the modulefile now owns). So when you
change what the modulefile exports, these are what prove a bare `module load` still
suffices. The same reasoning covers a suite an **end user** brings — a real Rose/Cylc
suite whose sources we do *not* stage — since we configure none of their toolchain
for them: it must work off the `module load` alone (see the top-level README's "Run
your own science suite"). The examples deliberately keep *their own* concerns (the
science-suite's per-task `WORKING_DIR`, source trees, and the Lustre HDF5 file-lock
workaround) but never re-derive the toolchain.

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

The minimal-compile example compiles differently per variant (see `examples/minimal-compile/build.sh`):
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

### Where the dependency versions come from (constraints)

The versions are not free choices — they are dictated upstream. Authoritative
sources, in priority order:

1. **`vendor/lfric_apps/dependencies.yaml`** — the single source of truth for the
   **LFRic source set**. A given `lfric_apps` ref pins the exact `lfric_core` +
   physics refs it must build against (jules/ukca by commit; casim/socrates/moci/
   socrates-spectral by tag). When you bump `lfric_apps`, **re-read this file and
   bump `vendor/lfric_core` + `vendor/physics/*` to match it** — that is exactly
   what `scripts/stage-physics.sh` consumes. Do not pick physics versions
   independently; our submodule pins are downstream of this file.
2. **`vendor/lfric_core/documentation/source/getting_started/installation/software_dependencies.rst`**
   — the Met Office **reference software stack** per release, plus the tested
   compilers. For the `2025.12.1` / apps-3.0 baseline it lists: gfortran 12.2.0 /
   Cray 15.0.0; Python 3.12.5; HDF5 1.14.5; netCDF C 4.9.2 / Fortran 4.6.1; mpich
   4.2.3; **PSyclone 3.2.2**; **fparser 0.2.1**; **YAXT 0.11.0**; **XIOS2 r2701**;
   **blitz 1.0.2**; **rose-picker 2.0.0**; **Rose 2.3.1 / Cylc 8+**; **PFUnit
   4.10.0**. These are the versions our `lfric-apps-isambard` package should track.
   The doc is per-release prose and can lag the checked-out tag — cross-check it
   against the rose-stem site configs below. **It did lag for 2026.07.1** (apps
   vn3.2): the `.rst` is byte-identical to the `2026.03.2` one and still says
   PSyclone 3.2.2, but the release actually needs **PSyclone ≥ 3.3** — see 4.
3. **`vendor/lfric_apps/rose-stem/site/meto/common/suite_config_*.cylc`** — the
   module versions the Met Office actually loads in CI (e.g. `module load
   xios/2701`, `xios/2701-oasis`). A reality check on the `.rst` prose. Note the
   MetO `ex1a`/`azspice` entries load opaque site modules (`lfric-gnu/12.2.0/3.2`,
   `lfric/vn3.2`), so for library versions the *other* sites are more informative —
   e.g. `site/esnz/common/suite_config_cascade.cylc` moved from
   `py-psyclone@3.1.0` (vn3.1.1) to `py-psyclone@3.3.1` (2026.07.1).
4. **The optimisation scripts themselves** (`applications/*/optimisation/*/psykal/`
   in apps + `infrastructure/build/psyclone/psyclone_tools.py` in core) — the
   *executable* statement of the PSyclone API version. `psyclone_tools.py` guards
   the moved imports with `try/except` ("Support for psyclone < 3.3"), but the
   apps-side scripts do not: at 2026.07.1 `lfric_atm/optimisation/meto-ex1a/psykal/
   algorithm/casim_alg_mod.py` does a bare `from psyclone.psyir.transformations
   import OMPParallelTrans`, which only exists from PSyclone 3.3. That is why the
   pin moved 3.2.2 → 3.3.1 for this release even though the `.rst` still says 3.2.2.
   Grep the optimisation scripts for `from psyclone` after every apps bump.

Where *we* encode the pins:

- **`spack-repo/lfric-isambard/packages/lfric-apps-isambard/package.py`** — the
  Spack-drawn pins: `py-psyclone@3.3.1`, `python@3.12`, `xios@2701`,
  `py-setuptools@:79`, etc.
- **`spack-repo/lfric-isambard/packages/xios/package.py`** — the XIOS revision +
  its build patch.

**`xios@2701` — read this before bumping it.** r2701 is what current LFRic wants
(the core docs and the MetO CI configs use **XIOS2 r2701**, and `mo-spack-packages`
ships `xios@2.2701` at the same commit); `mo-spack-packages` also ships
`xios@3.0.4.0` if a future move to XIOS 3 is wanted. We build r2701 from the migrated
Git history: former SVN r2701 maps to git `2eb572f0` on the `XIOS2` branch (commit
"Fix for recent compilers"). That commit already restores most STL includes the
older r2252 lacked, but earcut.hpp *still* comments out `<tuple>`/`<cstddef>` while
using `std::tuple_element`/`std::get`/`std::size_t`, which newer GCC/libstdc++ no
longer expose transitively — so we keep a minimal `gcc_remap_standard_headers.patch`
(`when @2701`) that just uncomments them (meshutil.cpp already `#include`s `<array>`
at r2701, so no meshutil hunk). Historical note: the previous pin was r2252 (git
`26cc7d88`, patched by `gcc12_remap_standard_headers.patch`), an *Isambard
build-pragmatic* choice carried from the upstream UniExeterRSE Isambard env. So
bumping XIOS again means: (a) add the new revision/commit to `xios/package.py`, (b)
check whether the header patch still applies / is still needed (regenerate it from
the pinned checkout — the earcut.hpp context drifts between revisions), (c) confirm
lfric links against it. Treat XIOS as the **highest-risk single bump** in the stack.

Pinned commits at time of writing (snapshot — `git submodule status` is authoritative):

| Submodule | Commit | Note |
|-----------|--------|------|
| `vendor/spack` | `3e19345b` | tag `v1.2.2` |
| `vendor/spack-packages` | `d4f7c711` | tag `v2026.06.0`, builtin packages |
| `vendor/lfric_apps` | `bd921320` | `2026.07.1` (= `vn3.2`) |
| `vendor/lfric_core` | `5d2a8b11` | `2026.07.1` (= `vn3.2`) |
| `vendor/mo-spack-packages` | `e6457de8` | the `metoffice` package repo |
| `vendor/physics/casim` | `396cccfe` | `2026.07.1` |
| `vendor/physics/jules` | `b698279d` | `2026.07.1` (= `vn8.2`) |
| `vendor/physics/socrates` | `3c9f48b8` | `2026.07.1` |
| `vendor/physics/ukca` | `612131bc` | `2026.07.1` |

For the `2026.07.1` coordinated release every Met Office repo's `stable` branch is
exactly its `2026.07.1` tag — there were no post-release patch tags at the time of
this bump (unlike the `2026.03` cycle, where apps `vn3.1.1` and several `stable`
heads ran ahead of the coordinated tag). Check `git log origin/stable` per repo
before assuming the tag is the newest thing.

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
| `PSYCLONE_TRANSFORMATION` | `minimum` | minimal-compile example: PSyclone optimisation set. |

## Adding things

- **A new dependency variant:** add `spack-env/<name>/spack.yaml` (include
  `../common.yaml`; set the MPI/IO provider + the manifest-only `view:`/`specs:`);
  extend the `case "$LFRIC_STACK"` validation + solve assertions in `build.sh` and
  the variant branch in `examples/minimal-compile/build.sh`; add the per-variant lib
  handling in `gen-modulefile.sh`/`lfric-env.lua` if it needs system libs like cray.
- **A new science example:** copy `examples/minimal-compile/` and change the build target
  + which physics deps you stage. The environment-activation block is reusable —
  it is the contract between Stage 1 and anything built on it.

## Testing

- **Static:** `bash -n scripts/*.sh examples/minimal-compile/build.sh`; `shellcheck` if available.
- **Cheap (login node):** `LFRIC_STACK=cray bash scripts/concretize.sh`
  → `CONCRETIZE_OK`; repeat with `LFRIC_STACK=spack`. Validates the manifest
  instantiation + variant assertions without the multi-hour install. Concretization
  is single-process and fine on the login node. (Add `FORCE_CONCRETIZE=1` to force a
  fresh re-solve rather than reuse a current lock.)
- **Full (compute node) — the invariant:** the four cases must build:
  `sbatch scripts/build.sbatch` (+ `--export=ALL,LFRIC_STACK=spack`) → `BUILD_OK`,
  then `sbatch examples/minimal-compile/build.sbatch` (+ spack) → `LFRIC_ATM_OK`.
  **Run the two minimal-compile variants SEQUENTIALLY, not in parallel.** Both
  compile in the same in-tree scratch dir
  (`vendor/lfric_apps/applications/lfric_atm/working/scratch/`), so concurrent jobs
  race on the source symlinks it stages and one dies with
  `FileNotFoundError: ... working/scratch/lfric_core` from `get_git_sources.py`.
  Chain them instead: `sbatch --dependency=afterany:<cray-jobid> ...`. (The two
  Stage-1 builds are worth chaining too — they share `$PREFIX/opt`.)
- **Integration (the examples are the test).** minimal-compile and the science-suites
  double as integration tests that a bare `module load` is a sufficient toolchain —
  they load the env like an end user and add nothing of their own to it. After
  changing `gen-modulefile.sh` / `lfric-env.lua` (what the module exports), re-run
  both minimal-compile variants and, on `cray`, at least one science suite
  (`bash examples/science-suites/run-suite.sh u-dn704` or `u-dr932`) — an end-user
  suite gets no toolchain setup from us, so this is what proves the `module load`
  alone still compiles + runs.
