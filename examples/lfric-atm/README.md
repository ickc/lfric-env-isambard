# Example: compile `lfric_atm` on the environment (Stage 2)

This directory is a **worked example of Stage 2**: building a science target on
top of the LFRic environment that Stage 1 produced. It compiles the `lfric_atm`
application and runs its small bundled example.

> The reproducible *core* of this repo is the **environment** (Stage 1,
> `scripts/build.sh`). This example is **not** that core — it is one thing you can
> do *with* the environment. Treat `build.sh` here as a **template** to copy and
> adapt for your own science suite. For full Rose/Cylc science suites, see the
> upstream [Isambard3-LFRic-Env-Science-Suites](https://github.com/UniExeterRSE/Isambard3-LFRic-Env-Science-Suites),
> whose `suites/u-*` directories live separately from the `env_lfric_*` build,
> mirroring this Stage 1 / Stage 2 split.

## What it does

1. Loads the built environment via Lmod (`module load lfric-env/<variant>`).
2. Sets the compiler + MPI/IO wrappers for the active variant
   (`cray`: Cray `ftn`/`CC`; `spack`: the view's `mpif90`/`mpic++`).
3. Runs `lfric_apps`' `local_build.py` to compile `lfric_atm`, using the **pinned
   physics submodules** under `vendor/physics/` (no build-time SSH/clone — see the
   reproducible-sources note in `MAINTAINER.md`).
4. Runs the bundled example (`applications/lfric_atm/example/configuration.nml`).

## Prerequisites

- **Stage 1 built** for the variant you want (`scripts/build.sbatch`). This example
  uses the environment; it does not build one.
- **Physics submodules initialised** (Stage-2 only):
  ```bash
  git submodule update --init --jobs 4 -- \
    vendor/physics/casim vendor/physics/jules vendor/physics/socrates vendor/physics/ukca
  ```
  (or `pixi run init-physics`). These are private Met Office repos — you need an
  SSH key authorised for Met Office SSO (see the top-level `README.md`).

## Run it

On a compute node (the compile is heavy), from the repo root:

```bash
# cray variant (default):
sbatch examples/lfric-atm/build.sbatch
# spack variant:
sbatch --export=ALL,LFRIC_STACK=spack examples/lfric-atm/build.sbatch
```

> **Build one variant at a time.** Both variants compile in the *same* lfric_apps
> working tree (`applications/lfric_atm/working/`), so running the two `lfric-atm`
> jobs **concurrently** corrupts the build (stale handles / locked dependency DB).
> Submit the second variant only after the first has finished. (The Stage-1 env
> builds, by contrast, are independent and may run at the same time.)

Interactively (small targets only — a full compile can exhaust the login node's
process limit), set the variant + prefix to match what you built, then run:

```bash
export LFRIC_STACK=cray                              # or spack
export LFRIC_PREFIX="$PROJECTDIR/$USER/opt/Linux-aarch64"   # the prefix you built into
module use "$LFRIC_PREFIX/modulefiles"
module load "lfric-env/$LFRIC_STACK"
bash examples/lfric-atm/build.sh
```

With pixi: `pixi run build-lfric-atm` (or `LFRIC_STACK=spack pixi run build-lfric-atm`).

A successful run ends with `LFRIC_ATM_OK`. The build log is written to
`$LFRIC_PREFIX/lfric_atm-make.log`.

## Knobs (env vars)

| Variable | Default | Purpose |
|----------|---------|---------|
| `LFRIC_STACK` | `cray` | Which built variant to compile against (`cray`/`spack`). Must match a built environment. |
| `LFRIC_PREFIX` | `$PROJECTDIR/$USER/opt/<arch>` | The prefix Stage 1 installed into (where the modulefile + view live). |
| `MAKE_JOBS` | `8` (sbatch: `$SLURM_CPUS_PER_TASK`) | Parallel make jobs. |
| `PSYCLONE_TRANSFORMATION` | `minimum` | PSyclone optimisation set under `applications/lfric_atm/optimisation/`. |
| `PROJECT` | `lfric_atm` | The application to build/run. |

## Adapting this for your own science target

Copy `build.sh` and change: `PROJECT` (and the `local_build.py … <app>` target),
the `PSYCLONE_TRANSFORMATION`, and which physics dependencies you stage. The
environment activation (the `module load` + the variant compiler/MPI wrapper
block) is reusable as-is — that part is the contract between Stage 1 and Stage 2.
