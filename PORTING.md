# Port your suite to Isambard 3

You have an LFRic Rose/Cylc suite that runs somewhere else, and you want it to run on
Isambard 3 against the `lfric-env` module. This is the checklist. Everything in it is
taken from the four suites this repo runs ([`examples/science-suites/`](examples/science-suites/))
and the rose-stem site ([`patches/rose-stem/`](patches/rose-stem/)); the links go to
the measurements and the worked examples.

The rule behind every item: the module provides the toolchain, and the suite consumes
it. Change only what the platform forces, and mark each change in place (this repo uses
an `[isambard3]` comment) with the reason, so the diff can be reviewed and later
upstreamed.

## 1. Load the module, and launch from that shell

```bash
module use "$PROJECTDIR/lfric-env/Linux-aarch64/modulefiles"
module load lfric-env/v2026.10.08/cray
```

Always use `cray`: it's the only variant whose MPI runs over Slingshot. The module puts
`rose`, `cylc`, `rosie` and `psyclone` on `PATH`. It also brings the Cylc site config,
which defines the `isambard3` platform and puts run directories under
`$PROJECTDIR/$USER`, and the Rose site config, which holds the rosie `u-` prefix map.
With the module loaded, `cylc vip` works as it does anywhere else.

## 2. Load the module in every job

Cylc runs each job in a login shell, which resets Lmod, so a job does not inherit the
module from the shell you launched from. Without a fix, jobs die with
`rose: command not found` before any `pre-script` runs. The module exports its own name
and location, so read them when the workflow is validated and load them in `init-script`,
the earliest hook there is:

```jinja2
{% set lfric_env_modulepath = environ["LFRIC_ENV_MODULEPATH"] %}
{% set lfric_env_module = environ["LFRIC_ENV_MODULE"] %}

[runtime]
    [[root]]
        init-script = """
            . /opt/cray/pe/lmod/lmod/init/bash
            module use {{ lfric_env_modulepath }}
            module load {{ lfric_env_module }}
        """
```

The rose-stem site does exactly this; see its `isambard3_env` in
[`patches/rose-stem/lfric_apps-isambard3-site.patch`](patches/rose-stem/lfric_apps-isambard3-site.patch).

## 3. Take the compiler from the module

The module exports `FC`, `LDMPI`, `CXX` and `FPP`, plus `FFLAGS` and `LDFLAGS` for
XIOS, HDF5, netCDF and shumlib. In the build task:

```ini
# flow.cylc [[[environment]]] or rose-app.conf [env]
FC = $FC
LDMPI = $LDMPI
FPP = $FPP
```

The Met Office EX suites hard-code `FC = mpif90`, which overrides the module's `ftn`
and breaks the build on `cray`. If your suite sets no compiler at all, there is
nothing to do. Never point `APPS_ROOT_DIR` or `CORE_ROOT_DIR` at anything but your
own extracted source.

## 4. Use the `isambard3` platform, and say where the ranks go

```ini
[[MODEL]]
    platform = isambard3
    [[[directives]]]
        --nodes = 1
        --ntasks = 96
        --ntasks-per-node = 96
        --exclusive =
        --mem = 0
```

- **`RUN_METHOD = srun`**, not `mpiexec`. The `cray` environment has no `mpiexec`, and
  `srun` is what puts cray-mpich on Slingshot. The Met Office `launch-exe` already
  handles `srun`. The one exception is a dedicated XIOS server: use
  [`examples/science-suites/site/bin/launch-exe`](examples/science-suites/site/bin/launch-exe),
  which runs client and server with `srun --multi-prog`.
- **`--nodes` and `--ntasks-per-node`, `--exclusive`, `--mem=0`.** Without these, Slurm
  spreads a job that fits on one node over whatever nodes have room, shares them with
  other users, and the model runs several times slower and with unreproducible timings.
  The measurements are in [`staging/dr932-mpi-scaling/`](staging/dr932-mpi-scaling/).
- **A Grace node has 144 cores**, not the 128 the Met Office suites assume. Fix any
  `CORES_PER_NODE`/`LPPN`.
- **A cubed-sphere mesh wants `6 × n²` ranks** for square subdomains: 24, 54 and 96
  fit on one node.
- If your platform uses `--export=NONE`, add `export SLURM_EXPORT_ENV=ALL` to the
  model task's `pre-script`. Otherwise `srun` steps start with an empty environment.
- Keep `OMP_NUM_THREADS=1` unless you mean to experiment. The binaries are built with
  OpenMP, but this repo has not measured the rank/thread balance.

Small jobs (extract, builds, mesh generation) don't need whole nodes: for example,
`--ntasks=1 --cpus-per-task=24 --mem=40G`.

## 5. Write output safely to Lustre

`cylc-run` lives on Lustre, which rejects the file locks HDF5 takes. Set
`HDF5_USE_FILE_LOCKING=FALSE` in the model task's environment. Otherwise XIOS stops
with "Permission denied" after creating an empty output file.

## 6. Match the namelists to the LFRic release

Your app configs must match the LFRic the environment builds (`2026.07.1`, apps
vn3.2), not the version the suite was written for. Use Rose's own upgrade, with the
release's rose-meta that the module provides:

```bash
export ROSE_META_PATH=$LFRIC_ROSE_META_PATH
cd <suite>/app && rose app-upgrade -y -C lfric_atm vn3.2 && rose macro --validate
```

Run it on a config that really is at the version its `meta=` line claims; a
hand-ported config confuses the macros. If your science needs code that isn't in the
release, express that in `dependencies.yaml` (a fork, or a branch merged onto a tag).
No namelist edit can supply it. The section
[Version alignment](examples/science-suites/README.md#version-alignment-forward-porting-suite-configs)
has both cases, with u-dt000 as the hard one.

## 7. Sources: keep `dependencies.yaml`

Keep your `dependencies.yaml` and the upstream `merge_sources.py` extract. Compute
nodes have outbound network, so the extract clones from GitHub as it does at the Met
Office. Set `USE_TOKENS=true` for HTTPS clones; the SSH form needs a key registered
with the Met Office organisation.

This repo also applies its LFRic source patches to the extracted tree
(`examples/science-suites/site/patch-sources.sh`). Most suites don't need them. The
one that matters for building `lfric_atm` is `30-lfric_apps-local-sources`, which
stops the apps build from re-cloning physics sources mid-compile.

## 8. Data

Ancillaries, start dumps and `um_aux` for the suites run here are staged under
`/projects/u35v/sw/lfricdata`. Point `BIG_DATA_DIR` (or your suite's equivalent)
there, or at your own copy.

## Worked examples

Each suite's README lists every change with its reason:

| suite | what it shows |
|---|---|
| [u-dr932](examples/science-suites/u-dr932/README.md) | the smallest port: one node, XIOS attached, `rose app-upgrade` from vn3.1 |
| [u-dn704](examples/science-suites/u-dn704/README.md) | two nodes and a dedicated XIOS server; no version gap |
| [u-dt000](examples/science-suites/u-dt000/README.md) | science that needs code no release has (an opt-in source patch) |
| [u-dz791](examples/science-suites/u-dz791/README.md) | an idealised training suite |
| [rose-stem site](patches/rose-stem/README.md) | an `isambard3` site for lfric_apps rose-stem |
