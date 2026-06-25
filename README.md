# lfric-env-isambard

A [pixi](https://pixi.sh)-driven, submodule-based, reproducible build of the
**LFRic Apps Spack environment** for **Isambard 3** (GCC 14.3).

> The Met Office packages come from
> [`mo-spack-packages`](https://github.com/MetOffice/mo-spack-packages) (the
> Spack-1.0-native successor to `simit-spack`); the cylc/rose workflow tools come
> from the vendored Spack builtin repo. See [Pinned versions](#pinned-versions).

This is a refactor of a single large `install.sh` driver into:

- **pixi** as the Stage-1 Python bootstrap *and* task runner — optional, since the
  built environment is `module`-loadable without it (see [Architecture](#architecture)),
- **git submodules** for every upstream source (Spack, the Spack package repo,
  and the Met Office repos), pinned to known-good commits,
- **standalone patch scripts** (`patches/*-patch.sh`) replacing the inline
  `sed`/`awk`/`perl`/heredoc patching that the driver used to do,
- an install **`PREFIX`** outside the repo (default
  `$PROJECTDIR/$USER/opt/<arch>`) for all heavy build output, so the built
  environment outlives the repo's location.

## Architecture

The repo turns pinned upstream sources into a **prebuilt, `module`-loadable LFRic
Apps environment**, in two stages. The key separation: **pixi matters only for
Stage 1, and even there it is optional** — it is not needed to *use* what gets
built.

```
Stage 1 — BUILD the environment        (Python 3.7–3.11: pixi, or cray-python/3.11.7)
  pinned submodules ─▶ Spack: concretize ─▶ install ─▶ view ─▶ generate modulefile
                                                                       │
                                                                       ▼
            product:  $PREFIX/modulefiles/lfric-env/<variant>.lua  (self-contained)
                                                                       │
Stage 2 — USE the environment          (just `module load`; no pixi, no Spack)
  module load lfric-env/<variant> ─▶ rose / cylc / psyclone / spack ...
                                  └─▶ compile a science suite (scripts/build-lfric-atm.sh)
```

**Stage 1 — build (needs Python 3.7–3.11 + the submodules).** Spack concretizes and
installs the whole stack (rose, cylc, psyclone, xios, mpi, ...) into
`$PREFIX/`, regenerates the env view, and — as its final step — writes a
self-contained **Lmod modulefile**. The only thing pixi contributes is the Python
that *runs* Spack (Spack 1.0 needs CPython <3.12); supply that yourself and pixi
is out of the picture (`build.sh` checks it up front).

**Stage 2 — use (needs only the Stage-1 modulefile).** Everything downstream loads
the environment with `module load lfric-env/<variant>`. That module is
self-contained — it puts the Spack view, the env's own Python, rose/cylc/psyclone,
shumlib and (for the `cray` variant) the Cray MPI/IO libraries on the right paths
with no nested `module load` — so **neither pixi nor Spack is needed** to use the
environment or to build a science suite on top of it. `scripts/build-lfric-atm.sh`
is precisely that: load the module, compile `lfric_atm`, run its example.

| | Stage 1 — build | Stage 2 — use / build a suite |
|---|---|---|
| Needs | Python 3.7–3.11 + submodules + Spack | the Stage-1 Lmod modulefile only |
| With pixi | `pixi run build` | `pixi run build-lfric-atm` |
| Without pixi | `module load cray-python/3.11.7` → `bash scripts/build.sh` | `module load lfric-env/<variant>` → `bash scripts/build-lfric-atm.sh` |

pixi therefore plays three roles, all confined to Stage 1: it **bootstraps** the
Python that runs Spack, **auto-activates** the built module on every `pixi run`
(a convenience — see [Activation](#activation)), and is the **task runner** for
the table under [Tasks](#tasks). Every task wraps a script in `scripts/`, so each
has a direct no-pixi equivalent (`bash scripts/<script>`).

## Quickstart

### Stage 1 — build the environment

With pixi (it supplies the Python that runs Spack):

```bash
pixi run submodule-init   # one-time: clone the pinned submodules (needs repo access)
pixi run build            # build the Spack environment (~2-4 h from scratch)
pixi run activate         # report rose / cylc / psyclone versions
```

Without pixi (bring your own Python 3.7–3.11 — Spack 1.0 needs CPython <3.12):

```bash
module load cray-python/3.11.7                      # or any python3 in [3.7,3.12)
git submodule update --init --recursive --jobs 4    # = submodule-init
bash scripts/build.sh                               # = build
bash scripts/print-versions.sh                      # = activate
```

The second dependency variant (mpich + HDF5/netCDF from source instead of the
Cray PE libraries) is selected with `LFRIC_STACK=spack`; it coexists with the
default and shares one install tree, so only the MPI subtree is rebuilt:

```bash
LFRIC_STACK=spack pixi run build          # or: pixi run build-spack
LFRIC_STACK=spack bash scripts/build.sh   # no-pixi equivalent
```

### Stage 2 — use the environment (no pixi required)

Once Stage 1 has written the modulefile, load it for a working environment — no
pixi, no Spack:

```bash
module use "$PREFIX/modulefiles"      # $PROJECTDIR/$USER/opt/<arch>/modulefiles; build prints it
module load lfric-env/cray            # or lfric-env/spack
rose --version; cylc --version; psyclone --version
```

`$PREFIX` is outside the repo, so this works even if the repo has since moved or
been deleted — the modulefile carries absolute paths to the install tree + view.

Optionally compile the `lfric_atm` science suite against it (uses the pinned
`vendor/physics/` submodules; no build-time SSH):

```bash
bash scripts/build-lfric-atm.sh       # with the module loaded as above
pixi run build-lfric-atm              # equivalent inside pixi (auto-loads the module)
```

`build-lfric-atm.sh` compiles against whichever variant you loaded (it adopts the
loaded module's `LFRIC_STACK`), so `module load lfric-env/spack` then the command
above builds the spack stack — no extra flag needed.

Inside pixi you can skip the explicit `module load`: after `build`, **every**
`pixi run ...` (and `pixi shell`) auto-activates the environment via Lmod (see
[Activation](#activation)), so `pixi run rose --version` / `pixi run spack find`
work directly.

Expected result after a complete build (exact rose/cylc versions track the
vendored Spack builtin repo; psyclone comes from mo-spack-packages):

```
rose 2.4.2
cylc 8.4.2
PSyclone version: 3.2.2
```

## Tasks

| Task | What it does |
|------|--------------|
| `submodule-init` | Clone the pinned submodules under `vendor/`. Run once. |
| `stage-physics` | Set the physics + `lfric_core` submodules to their `dependencies.yaml` refs (then commit the gitlinks). The explicit way to pull in new science. |
| `patch` | Apply every `patches/*-patch.sh` (sorted, idempotent). |
| `unpatch` | Revert all patches by resetting the patched submodules. |
| `build` | Build the Spack environment, **cray** variant (applies patches, concretizes, installs). |
| `build-spack` | Same, **spack** variant — `mpich` + HDF5/netCDF from source (`LFRIC_STACK=spack`). |
| `build-lfric-atm` | Optionally compile `lfric_atm` + run its example (uses the pinned `vendor/physics/` submodules; no build-time SSH). |
| `activate` | Activate + print rose/cylc/psyclone versions (cray variant). |
| `activate-spack` | Same for the spack variant (`LFRIC_STACK=spack`). |
| `verify-xios` | Check the migrated XIOS source matches the pinned commit. |
| `clean` | Remove the build output under `$WORKING_DIR` (= `PREFIX`; keeps submodules and patches). |

`pixi run spack ...` works because activation puts the vendored Spack on `PATH`
(`vendor/spack`). The tracked `spack-env/<variant>/spack.yaml` are **templates**:
`build` instantiates the real directory environment under `PREFIX`
(`$PREFIX/spack-env/<variant>/`, rewriting the template's relative
`include: ../common.yaml` to an absolute path back into the repo), so the env's
generated `.spack-env/` view + lockfile land outside the repo. The shared
`common.yaml` (and its relative `repos:`) stays tracked in the repo.
`LFRIC_STACK` (default `cray`) selects which variant every task operates on.

Each task is a thin wrapper around a script in `scripts/`; without pixi, run that
script directly for the same effect (e.g. `bash scripts/build.sh`, or
`git submodule update --init --recursive` for `submodule-init`).

## Activation

The built environment is loaded through **Lmod**, so **pixi is only needed to
_build_ it** — once built, loading the environment needs nothing but `module`.
It is self-contained — it puts the resolved Spack view + package prefixes on
`PATH`/`PYTHONPATH`/`SHUMLIB_ROOT`/`LD_LIBRARY_PATH`/`SPACK_ENV`/… with no nested
`module load` — so it is fast and works under `/bin/sh`.

To stay auditable, the modulefile is split in two:

- **Logic** — [`scripts/lfric-env.lua`](scripts/lfric-env.lua): version-controlled,
  syntax-highlighted Lua holding all the `setenv`/`prepend_path`/`pushenv` rules.
  Audit it once. `build` snapshots a byte-identical copy to
  `$PREFIX/modulefiles/lfric-env.lua` so loading is repo-independent.
- **Data** — `$PREFIX/modulefiles/lfric-env/<variant>.lua` (generated per
  build by `scripts/gen-modulefile.sh`): a flat table of the per-build paths,
  ending in `assert(loadfile("$PREFIX/modulefiles/lfric-env.lua"))(data)`. Trivial
  to eyeball/diff.

(Lmod's Lua sandbox forbids `dofile()` but allows `loadfile()` + passing the
table as an argument, which is how the two halves connect.)

- **Inside pixi** (the usual path): nothing to do — every `pixi run ...` /
  `pixi shell` auto-activates the `LFRIC_STACK` variant. `common.sh` puts
  `$PREFIX/modulefiles` on `MODULEPATH` and `activate.sh` `module load`s
  `lfric-env/$LFRIC_STACK`.
- **Outside pixi** (a Slurm job, a plain login shell — no pixi required):

  ```bash
  module use "$PREFIX/modulefiles"     # $PROJECTDIR/$USER/opt/<arch>/modulefiles
  module avail lfric-env               # -> lfric-env/cray, lfric-env/spack
  module load lfric-env/cray           # or lfric-env/spack
  ```

  The two share the module name `lfric-env`, so loading one **swaps out** the
  other; bare `module load lfric-env` resolves to the default (`cray`).

The modulefiles live under `$PREFIX` (outside the repo), so they are not
tracked (their paths contain per-build content hashes). Regenerate one without a
full rebuild — e.g. after moving `$PREFIX` — with:

```bash
bash scripts/gen-modulefile.sh                 # cray (default)
LFRIC_STACK=spack bash scripts/gen-modulefile.sh
```

## Layout

```
pixi.toml                 # pixi project: deps, activation hook, tasks
spack-env/                # Spack env TEMPLATES (tracked); `build` instantiates under PREFIX
  common.yaml             #   shared config included by both variants (repos, gcc, python)
  cray/spack.yaml         #   variant: system cray-mpich + Cray HDF5/netCDF (default)
  spack/spack.yaml        #   variant: mpich + HDF5/netCDF built from source
spack-repo/lfric-isambard # local repo: "lfric-apps-isambard" bundle, xios, foxml
vendor/                   # submodules (pinned)
  spack/                  # spack/spack
  spack-packages/         # spack/spack-packages (Spack builtin packages)
  lfric_apps/             # MetOffice/lfric_apps
  lfric_core/             # MetOffice/lfric_core
  mo-spack-packages/      # MetOffice/mo-spack-packages (the "metoffice" repo)
  physics/                # MetOffice casim/jules/socrates/ukca (lfric_atm science)
patches/                  # one *-patch.sh per upstream patch (sorted by prefix)
scripts/                  # common.sh, activate.sh, build.sh, gen-modulefile.sh, ...
  lfric-env.lua           #   Lmod modulefile logic (data table generated per build)
logs/                     # sbatch stdout (#SBATCH --output=logs/...); .gitkeep tracked
$PREFIX/                  # outside the repo (default $PROJECTDIR/$USER/opt/<arch>):
  opt/ stage/ *-cache/    #   Spack install tree + build/source/misc caches
  spack-env/<variant>/    #   instantiated directory env + .spack-env/ view + lockfile
  modulefiles/lfric-env/  #   generated Lmod modulefiles (cray.lua, spack.lua)
```

## Pinned versions

The authoritative pins live in the git index (`git submodule status`); the
table below is a convenience snapshot:

| Submodule | Commit |
|-----------|--------|
| `vendor/spack` | `7ae1d68c` (develop, Spack 1.0.x) |
| `vendor/spack-packages` | `7e330489` (builtin, 2025-11-12) |
| `vendor/lfric_apps` | `b5aee0b1` (vn3.1.1-88) |
| `vendor/lfric_core` | `bf236737` (2026.03.2-38) |
| `vendor/mo-spack-packages` | `5e8359e0` (the `metoffice` package repo) |
| `vendor/physics/casim` | `b0a6e38f` (2026.03.2) |
| `vendor/physics/jules` | `3647a429` (2026.03.2-14) |
| `vendor/physics/socrates` | `fb97f50a` (2026.03.2) |
| `vendor/physics/ukca` | `1cdb9c26` (2026.03.2-5) |

## Patches

Each patch is a standalone, idempotent `patches/<NN>-<target>-patch.sh`,
applied in sorted order by `patch-all.sh` (discovered dynamically — names are
not hardcoded):

- `10-lfric_core-*`, `11-lfric_core-*` — Fortran/Make fixes in `vendor/lfric_core`.
- `20-spack-packages-papi-*`, `21-spack-packages-papi-*` — papi build fixes in
  `vendor/spack-packages` (no-ops at the pinned commit, kept as guards against a
  submodule bump).
- `22-spack-packages-gdbm-automake-patch.sh` — gdbm `automake` build fix in
  `vendor/spack-packages`.
- `30-lfric_apps-local-sources-patch.sh` — rewrites `get_source()` in
  `vendor/lfric_apps` so the build stages the pinned `lfric_core` + physics
  submodules in place instead of cloning/fetching them at build time (see
  *Reproducible, offline science sources* under Notes).

The Met Office package definitions are **no longer patched**: the old
`simit-spack` repo (Spack < 1.0) needed ~40 `30-/40-simit-*` patch scripts to
work under Spack 1.0, but its replacement, `mo-spack-packages`, is Spack-1.0
native (`api: v2.0`), and the cylc/rose workflow tools it used to carry now ship
in the Spack builtin repo. Those patches were therefore removed in the port.

Because every remaining patch modifies files **inside a submodule** (overwriting
tracked files), `pixi run unpatch` reverts them all by `git reset --hard &&
git clean -fd` on `lfric_core`, `lfric_apps`, and `spack-packages`. `build`
re-applies patches automatically, so it is always self-contained.

## Notes / caveats

- **Build output location (`PREFIX`).** Everything heavy (~7.5 GB) — the Spack
  install tree, the per-variant environment *and its view*, the generated
  modulefiles and the caches — goes under **`PREFIX`**, which defaults **outside
  the repo**: `$PROJECTDIR/$USER/opt/<sysname>-<machine>` (e.g.
  `$PROJECTDIR/$USER/opt/Linux-aarch64`; falls back to `$SCRATCH`/`$HOME` when
  `$PROJECTDIR` is unset). This is deliberate: the Spack *view* (the symlink farm
  that lands on `PATH`) used to live inside the repo, which tied Stage 2 to the
  repo's path — now it is under `PREFIX`, so once Stage 1 is built the repo can
  move or be deleted and `module load lfric-env/<variant>` still works (see
  [Architecture](#architecture)). The build also redirects Spack's user config
  and cache under `PREFIX` (`SPACK_USER_CONFIG_PATH`, `SPACK_USER_CACHE_PATH`), so
  it neither reads nor writes your global `~/.spack`. Override with `LFRIC_PREFIX`
  (whole tree) or `LFRIC_WORKING_DIR` (just the output dir). Stage 1, the *build*,
  still needs the repo: the vendored Spack + pinned package repos live here.
- **GCC 14.3.** The compiler is declared as an explicit external in
  `spack-env/common.yaml` (`gcc@14.3.0` → `/usr/bin/{gcc,g++,gfortran}-14`) and
  pinned via per-language `require`s, so the solve is deterministic and `build`
  does *not* run `spack compiler find`. It is shared by both variants. Isambard 3
  previously shipped a complete `gcc@12.3.0` toolchain (used by earlier builds)
  but that has been reduced to a C-only compiler (no `g++`/`gfortran` 12.3);
  `gcc@14.3.0` is now the only complete cray-native C/C++/Fortran toolchain. To
  target a different gcc, edit the external + `require`s in `common.yaml`.
- **Dependency variants (`cray` / `spack`).** The MPI + parallel I/O stack is
  selectable via **`LFRIC_STACK`** (default `cray`). Each variant is its own Spack
  directory environment under `spack-env/<variant>/`, both `include:`-ing the
  shared `spack-env/common.yaml` (repos, the `gcc@14.3.0` external, python). They
  **share one install tree** (`$PREFIX/opt`): Spack's content-addressed store
  builds the large MPI-independent subtree (python/rose/cylc/psyclone/…) once and
  links both views to it; only the MPI-dependent subtree (mpi, hdf5, netcdf, yaxt,
  xios, shumlib, lfric) is built per variant. So both environments coexist and
  activate independently (`pixi run activate` vs `LFRIC_STACK=spack pixi run
  activate`) without rebuilding the world. `build` asserts the concretized lock
  actually matches the requested variant, so a mis-resolved external can't
  silently produce the wrong stack.
  - **`cray`** (default) uses the system **cray-mpich** (Cray PE, `PrgEnv-gnu`)
    plus the Cray **parallel HDF5/netCDF** as externals (`buildable: false`);
    `build` loads `PrgEnv-gnu` + `craype-arm-grace` + `cray-hdf5-parallel` +
    `cray-netcdf-hdf5parallel`. cray-mpich 9.1.0 is a `gnu/12.3` build, but its
    Fortran modules are *GFORTRAN module version 15* — which `gcc@14.3.0` also
    emits — so `use mpi` / `use mpi_f08` compile cleanly against it. Because the
    concretizer prunes an external's dependencies, the `libfabric`/`pmi`/`pals`
    library directories are injected through the externals' `extra_attributes` so
    dependents link and run.
  - **`spack`** builds **`mpich` + HDF5/netCDF from source**, loading no Cray
    modules (the `gcc` external is the always-present `/usr/bin/gcc-14`). HDF5,
    netCDF-c and netCDF-fortran are pinned to the **same versions** the cray
    variant externalizes (`1.14.3` / `4.9.2` / `4.6.1`, with matching `+mpi`
    variants) so the downstream DAG concretizes identically — the two stay
    apples-to-apples. It is the portable fallback; from-source `mpich` will not
    use the Slingshot/`cxi` fabric unless built with libfabric, so it is for
    correctness/CI/comparison rather than production runs. The `build-lfric-atm`
    compile for this variant uses the view's `mpif90`/`mpic++` wrappers (which
    lfric_core maps to its gfortran/g++ flag sets via `fortran/mpif90.mk` /
    `cxx/mpic++.mk`) instead of the Cray `ftn`/`CC`. Both variants are validated
    end-to-end on a `grace` node (env build + `lfric_atm` compile + example run;
    spack on `mpich@5.0.1`).
- **MetOffice SSH/SSO.** The private Met Office submodules (`lfric_apps`,
  `lfric_core`, `mo-spack-packages`, and the physics repos under
  `vendor/physics/`: `casim`, `jules`, `socrates`, `ukca`) are cloned over SSH
  and require an SSH key authorized for `MetOffice` SAML SSO (GitHub → Settings →
  SSH keys → Configure SSO), or an HTTPS credential helper (`gh auth setup-git`).
  If `submodule-init` fails on one of them, that is the usual cause.
- **Build on a compute node — keep the job small and short.** The Isambard 3
  login nodes cap user processes at `ulimit -u` 900, which a full parallel build
  (and pixi's first-time env solve) can exhaust (`fork: Resource temporarily
  unavailable`). Run the build on a `grace` compute node with the provided batch
  script:

  ```bash
  sbatch scripts/build.sbatch        # from the repo root
  ```

  The `grace` partition is usually full, so request a **small, short,
  non-exclusive** job: it backfills into the schedule far sooner than a
  whole-node (`--exclusive`) reservation. The build is not CPU-bound past ~16–24
  cores (past builds finished in ~50–70 min on 16–32 cores). This project uses
  **24 cores** (so `SPACK_JOBS`/`MAKE_JOBS=24`). The directives `build.sbatch`
  uses — copy these if rolling your own job:

  ```bash
  #SBATCH --partition=grace
  #SBATCH --ntasks=1
  #SBATCH --cpus-per-task=24     # 24 gives compiles memory headroom (see below) + speed
  #SBATCH --mem-per-cpu=1600M    # pro-rata share: 230400 MB / 144 cores = 1600 MB/core
  #SBATCH --time=03:30:00        # builds take <70 min; a short limit backfills sooner
  ```

  **Memory is pro-rata, and the default is too small.** On grace, memory is a
  consumable resource (`CR_CORE_MEMORY`): a node has `RealMemory=230400 MB` across
  144 cores = **1600 MB/core** (probe with `scontrol show node <grace-node>`).
  Slurm's *default* allocation (~1 GiB/core, e.g. 12 GiB for a 12-core job) is too
  little — heavy C++ translation units (xios' `group_template_decl`, node-js/rust's
  LLVM/V8) **OOM-kill `cc1plus`** ("Killed signal terminated program cc1plus")
  under it. Always set **`--mem-per-cpu=1600M`** (a node's full per-core share) so
  memory scales with `--cpus-per-task`; do *not* use a flat `--mem` far above the
  core-share, as that inflates the job's footprint and delays scheduling. 24 cores
  ⇒ 24 × 1600 MB = **37.5 GiB**, ample headroom. (`build.sh` also caps the known
  memory-hog packages at `HEAVY_JOBS` as a second line of defence — see the
  memory/OOM note at the end.) If a future build still OOMs, raise
  `--cpus-per-task` further: memory rises with it automatically.

  Build the **spack** variant on a node by passing the selector through Slurm:

  ```bash
  sbatch --export=ALL,LFRIC_STACK=spack scripts/build.sbatch
  sbatch --export=ALL,LFRIC_STACK=spack scripts/build-lfric-atm.sbatch
  ```

  Both batch scripts honour **`LFRIC_USE_PIXI=0`** for the no-pixi path on a node:
  the build job then `module load`s `cray-python/3.11.7` (override with
  `CRAY_PYTHON_MODULE`) and runs `scripts/build.sh` directly; the lfric_atm job
  just runs `scripts/build-lfric-atm.sh` (the Lmod module supplies its Python):

  ```bash
  sbatch --export=ALL,LFRIC_USE_PIXI=0 scripts/build.sbatch
  sbatch --export=ALL,LFRIC_USE_PIXI=0 scripts/build-lfric-atm.sbatch
  ```

  Avoid `--exclusive`/whole-node requests and multi-hour `--time` limits — both
  push the job behind the partition's reservations. `SPACK_JOBS` defaults to
  `$SLURM_CPUS_PER_TASK`. Concretization alone is single-process and fine on the
  login node.
- **Build stage on node-local disk (avoid Lustre contention).** Spack's compile
  stage is metadata-heavy (autotools/libtool touch thousands of small files). On
  a busy `grace` node the shared Lustre (`$PREFIX`/`$SCRATCH`) can be so contended
  that the *install* phase crawls — a build that normally finishes in <70 min can
  blow past a 3.5 h limit (e.g. a single `ncurses`/`gettext` install taking tens
  of minutes to an hour). `build` therefore stages on the **node-local NVMe**
  (`$LOCALDIR`/`/local` — a real 3.5 TB SSD on Isambard grace nodes, *not* the
  install tree, which stays on `$PREFIX` for persistence + correct RPATHs). It
  auto-probes for a writable local disk and **skips a small `tmpfs` RAM disk**
  (where `$LOCALDIR` is a RAM disk, staging would eat node memory and risk OOM) —
  see `LFRIC_BUILD_STAGE` / `LFRIC_TMPFS_MIN_GIB` in [Useful overrides](#useful-overrides).
  The stage is per-node and transient, so a re-run on another node just re-stages;
  the install tree on `$PREFIX` persists, so completed packages are still skipped.
- **lfric_atm** is intentionally not part of `build`: it needs the private
  physics repos (casim/jules/socrates/ukca), vendored as pinned submodules under
  `vendor/physics/` and consumed via `PHYSICS_ROOT`, so the compile itself does
  no build-time cloning. The Spack environment is complete without it.
- **Reproducible, offline science sources.** `local_build.py` upstream
  auto-clones/rsyncs/git-fetches the science sources during the build (which can
  silently change the stack). `patches/30-lfric_apps-local-sources-patch.sh`
  disables that: `get_source()` now symlinks the **staged** submodules in place
  and sanity-checks them — a remote source raises instead of fetching. So the
  compile is a pure function of the checked-out submodule SHAs (`lfric_core` +
  `vendor/physics/*`). To pull in new science, bump the refs in
  `vendor/lfric_apps/dependencies.yaml`, run `pixi run stage-physics`, and commit
  the updated gitlinks — never a silent build-time change.

## Useful overrides

| Variable | Default | Purpose |
|----------|---------|---------|
| `LFRIC_STACK` | `cray` | Dependency variant: `cray` (system cray-mpich + Cray HDF5/netCDF) or `spack` (mpich + HDF5/netCDF from source). Selects the `spack-env/<variant>/` environment for every task |
| `SPACK_JOBS` | `8` | Parallel Spack make jobs (raise on a dedicated compute node; keep modest on a shared login node) |
| `HEAVY_JOBS` | `6` | Make jobs for LLVM/V8-bundling packages (`node-js`, `rust`); capped to avoid OOM (see below) |
| `HEAVY_PKGS` | `node-js rust xios` | Memory-hungry packages built first at `HEAVY_JOBS` before the rest (`xios`' `group_template_decl.cpp` is a heavy template unit) |
| `MAKE_JOBS` | `8` | Parallel make jobs for `lfric_atm` |
| `LFRIC_PREFIX` | `$PROJECTDIR/$USER/opt/$(uname -sm \| tr ' ' -)` | Install prefix: where **all** Stage-1 output lands (install tree, env + view, modulefiles, caches). Defaults **outside the repo** so Stage 2 is repo-independent. Falls back to `$SCRATCH`/`$HOME` for `$PROJECTDIR` |
| `LFRIC_WORKING_DIR` | `$LFRIC_PREFIX` | Build-output directory; defaults to `PREFIX`. Set this for finer control, or `LFRIC_PREFIX` to relocate the whole tree |
| `LFRIC_BUILD_STAGE` | node-local NVMe (`$TMPDIR`/`$LOCALDIR`/`/local`), else `$WORKING_DIR/stage` | Spack's transient compile area. `build` auto-picks a fast node-local disk to keep the metadata-heavy install phase off the shared Lustre (which can be badly contended); set this to force a location. See the compute-node note below |
| `LFRIC_STAGE_MIN_GIB` / `LFRIC_TMPFS_MIN_GIB` | `20` / `60` | Min free space `build` requires of a node-local stage before using it — higher for a RAM-disk (`tmpfs`) candidate, since staging there consumes node memory |
| `PRGENV_MODULE` | `PrgEnv-gnu` | _cray variant only_: Cray PE module loaded by `build`; puts the `cray-mpich`/`libfabric`/`cray-pmi` externals on the module path + sets the `CRAY_*` lib paths (required) |
| `CRAYPE_TARGET` | `craype-arm-grace` | _cray variant only_: Cray CPU-target module (Grace / Neoverse-V2) |
| `HDF5_MODULE` / `NETCDF_MODULE` | `cray-hdf5-parallel/1.14.3.9` / `cray-netcdf-hdf5parallel/4.9.2.3` | _cray variant only_: parallel Cray HDF5/netCDF modules backing the `hdf5`/`netcdf` externals |
| `RUN_XIOS_VERIFICATION` | `1` | Set `0` to skip the XIOS network check in `build` |
| `CYLC_RUN_BASE` | `$PROJECTDIR/$USER/cylc-run` | Cylc run directory |

**Memory / OOM.** `node-js` (V8), `rust` (LLVM) and `xios` (`group_template_decl.cpp`)
have translation units that use several GB each; at high `-j` under a tight memory
allocation they get OOM-killed (`cc1plus: Killed signal`). Two defences: (1) on a
compute node, request enough memory — grace allocates memory **pro-rata** at
1600 MB/core, and the Slurm default (~1 GiB/core) is too little, so the batch
scripts set `--mem-per-cpu=1600M` with 24 cores (⇒ 37.5 GiB); see the compute-node
note under [Notes](#notes--caveats). (2) `build` installs the `HEAVY_PKGS` first at
`HEAVY_JOBS` (default 6) and the rest at `SPACK_JOBS`, so the hogs never compile at
full width. On a busy login node also use a modest `SPACK_JOBS` (≤16).
