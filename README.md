# lfric-env-isambard

A [pixi](https://pixi.sh)-driven, submodule-based, reproducible build of the
**LFRic Apps Spack environment** for **Isambard 3** (GCC 14.3).

> The Met Office packages come from
> [`mo-spack-packages`](https://github.com/MetOffice/mo-spack-packages) (the
> Spack-1.0-native successor to `simit-spack`); the cylc/rose workflow tools come
> from the vendored Spack builtin repo. See [Pinned versions](#pinned-versions).

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
| `build` | Build the Spack environment (applies patches, concretizes, installs). |
| `build-lfric-atm` | Optionally compile `lfric_atm` + run its example (uses the pinned `vendor/physics/` submodules; no build-time SSH). |
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
spack-repo/lfric-isambard # local repo: "lfric-apps-isambard" bundle, xios, foxml
vendor/                   # submodules (pinned)
  spack/                  # spack/spack
  spack-packages/         # spack/spack-packages (Spack builtin packages)
  lfric_apps/             # MetOffice/lfric_apps
  lfric_core/             # MetOffice/lfric_core
  mo-spack-packages/      # MetOffice/mo-spack-packages (the "metoffice" repo)
patches/                  # one *-patch.sh per upstream patch (sorted by prefix)
scripts/                  # common.sh, activate.sh, build.sh, build-lfric-atm.sh, ...
working_dir/              # git-ignored: Spack install tree, caches, env view, logs
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

The Met Office package definitions are **no longer patched**: the old
`simit-spack` repo (Spack < 1.0) needed ~40 `30-/40-simit-*` patch scripts to
work under Spack 1.0, but its replacement, `mo-spack-packages`, is Spack-1.0
native (`api: v2.0`), and the cylc/rose workflow tools it used to carry now ship
in the Spack builtin repo. Those patches were therefore removed in the port.

Because every remaining patch modifies files **inside a submodule** (overwriting
tracked files), `pixi run unpatch` reverts them all by `git reset --hard &&
git clean -fd` on `lfric_core` and `spack-packages`. `build` re-applies patches
automatically, so it is always self-contained.

## Notes / caveats

- **Build output location.** Everything heavy (~7.5 GB) goes under
  `working_dir/` next to the repo. The build redirects Spack's user config and
  cache there too (`SPACK_USER_CONFIG_PATH`, `SPACK_USER_CACHE_PATH`), so it
  neither reads nor writes your global `~/.spack`. Put the repo on a filesystem
  with space (e.g. `$SCRATCH`), or set `LFRIC_WORKING_DIR` to relocate output.
- **GCC 14.3.** The compiler is declared as an explicit external in
  `spack-env/spack.yaml` (`gcc@14.3.0` → `/usr/bin/{gcc,g++,gfortran}-14`) and
  pinned via per-language `require`s, so the solve is deterministic and `build`
  does *not* run `spack compiler find`. Isambard 3 previously shipped a complete
  `gcc@12.3.0` toolchain (used by earlier builds) but that has been reduced to a
  C-only compiler (no `g++`/`gfortran` 12.3); `gcc@14.3.0` is now the only
  complete cray-native C/C++/Fortran toolchain. To target a different gcc, edit
  the external + `require`s in `spack.yaml`.
- **Cray MPI (`cray-mpich`).** The environment uses the system **cray-mpich**
  (Cray PE, `PrgEnv-gnu`) as its MPI instead of building `mpich` from source:
  `spack.yaml` sets `mpi: [cray-mpich]` and declares `cray-mpich`/`libfabric`/
  `cray-pmi` as externals, and `build` loads `PrgEnv-gnu` + `craype-arm-grace`.
  cray-mpich 9.1.0 is a `gnu/12.3` build, but its Fortran modules are *GFORTRAN
  module version 15* — which `gcc@14.3.0` also emits — so `use mpi` / `use
  mpi_f08` compile cleanly against it. Because the concretizer prunes an
  external's dependencies, the `libfabric`/`pmi`/`pals` library directories are
  injected through cray-mpich's `extra_attributes` so dependents link and run.
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
  sbatch scripts/build.sbatch        # from the repo root; account brics.e5a
  ```

  The `grace` partition is usually full, so request a **small, short,
  non-exclusive** job: it backfills into the schedule far sooner than a
  whole-node (`--exclusive`) reservation, and the build is not CPU-bound past
  ~16 cores (past builds finished in ~50–70 min on 16–32 cores). The directives
  `build.sbatch` uses — copy these if rolling your own job:

  ```bash
  #SBATCH --partition=grace
  #SBATCH --account=brics.e5a
  #SBATCH --ntasks=1
  #SBATCH --cpus-per-task=16     # backfills fast; raise to 32 only if the queue is empty
  #SBATCH --time=03:30:00        # builds take <70 min; a short limit backfills sooner
  ```

  Avoid `--exclusive`/whole-node requests and multi-hour `--time` limits — both
  push the job behind the partition's reservations. `SPACK_JOBS` defaults to
  `$SLURM_CPUS_PER_TASK`. Concretization alone is single-process and fine on the
  login node.
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
| `SPACK_JOBS` | `8` | Parallel Spack make jobs (raise on a dedicated compute node; keep modest on a shared login node) |
| `HEAVY_JOBS` | `6` | Make jobs for LLVM/V8-bundling packages (`node-js`, `rust`); capped to avoid OOM (see below) |
| `HEAVY_PKGS` | `node-js rust` | Packages built first at `HEAVY_JOBS` before the rest |
| `MAKE_JOBS` | `8` | Parallel make jobs for `lfric_atm` |
| `LFRIC_WORKING_DIR` | `<repo>/working_dir` | Where build output lands |
| `PRGENV_MODULE` | `PrgEnv-gnu` | Cray PE module loaded by `build`; provides the `gcc@14.3` compiler + the `cray-mpich`/`libfabric`/`cray-pmi` externals (required) |
| `CRAYPE_TARGET` | `craype-arm-grace` | Cray CPU-target module (Grace / Neoverse-V2) |
| `RUN_XIOS_VERIFICATION` | `1` | Set `0` to skip the XIOS network check in `build` |
| `CYLC_RUN_BASE` | `$PROJECTDIR/$USER/cylc-run` | Cylc run directory |

**Memory / OOM.** `node-js` (V8) and `rust` (LLVM) have translation units that use
several GB each; at high `-j` on a swapless or shared node they get OOM-killed
(`cc1plus: Killed signal`). `build` therefore installs the `HEAVY_PKGS` first at
`HEAVY_JOBS` (default 6) and the rest at `SPACK_JOBS`. On a busy login node use a
modest `SPACK_JOBS` (≤16); on a dedicated compute node with plenty of RAM you can
raise both.
