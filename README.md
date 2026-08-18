# lfric-env-isambard

A reproducible build of the **LFRic Apps Spack environment** for the
**Isambard 3** supercomputer (GCC 14.3, Grace/aarch64). It turns a set of pinned
source repositories into a ready-to-use environment you load with one `module`
command — giving you `rose`, `cylc`, `psyclone`, `xios` and the full LFRic
dependency stack, without you having to drive Spack yourself.

You do **not** need to know Spack or [pixi](https://pixi.sh) to use this repo.
The steps below use plain `git`, `module` and `sbatch`. A pixi shortcut is
offered separately at the end for those who want it.

## The build, and two tiers of example

One prerequisite build (Stage 1), then examples you run *on* the built env. The
examples are **siblings**, not later "stages" — each depends only on Stage 1.

```
Stage 1  —  BUILD the environment            (run once; heavy; on a compute node)
  stage1/ :  pinned sources ─▶ Spack ─▶ a loadable module under $LFRIC_BASE

Example: minimal-compile  —  USE the env to compile a target   (lightweight)
  module load lfric-env/<version>/<variant> ─▶ rose / cylc / psyclone / spack …
                                   └▶ compile lfric_atm (examples/minimal-compile/)

Example: science-suites   —  RUN a real suite   (cylc on the login node ─▶ Slurm)
  cylc vip a Rose/Cylc LFRic suite on the built env (examples/science-suites/)
```

- **Stage 1** lives entirely in [`stage1/`](stage1/) and is the reproducible core of
  this repo — the one true prerequisite. It is self-contained: its own submodules,
  its own version, its own pixi workspace (the one place pixi is required, because
  it supplies the Python that runs Spack). It produces a self-contained Lmod
  modulefile under `$LFRIC_BASE`. **Everything you need to build it is in
  [`stage1/README.md`](stage1/README.md).** (We keep the name "Stage 1"; the
  examples below build on it rather than following it as stages.)
- **The minimal-compile example** (`examples/minimal-compile/`) is the smallest thing
  you do *with* the built env: compile the `lfric_atm` target, no science run. It needs
  only the modulefile — no Spack, no pixi, and the repo can even have moved or been
  deleted. Adapt it for your own science target.
- **The science-suite examples** (`examples/science-suites/`) run real Rose/Cylc suites
  on the built env the way scientists do — `cylc` schedules the suite and submits to
  Slurm; each suite declares its LFRic source refs in `dependencies.yaml` and compiles
  its own `lfric_atm` (e.g. `pixi run run-suite u-dr932`, on the default `cray` env).
  Each suite is the upstream tree itself plus a patch, so what we changed for Isambard 3
  is a reviewable diff — but they live in two different places, so getting one differs:
  u-dr932 is a pinned submodule (`pixi run init-suites` first), while u-dn704 and
  u-dt000 are Met Office rose suites in MOSRS subversion that you check out yourself
  with `rosie checkout` (needs a MOSRS account). `run-suite.sh` prints the exact command
  if the checkout is missing.

There are **two dependency variants**, chosen with `LFRIC_STACK`:

| `LFRIC_STACK` | MPI + parallel I/O | Use for |
|---------------|--------------------|---------|
| `cray` (default) | system **cray-mpich** + Cray parallel HDF5/netCDF | production runs on Isambard |
| `spack` | **mpich** + HDF5/netCDF **built from source** | portability / CI / comparison |

So there are four things you can build: {the env build (Stage 1), the minimal-compile
example} × {`cray`, `spack`}.

## Prerequisites

- **An Isambard 3 account**, and the basics of using it: the difference between a
  **login node** (where you clone + submit jobs) and a **compute node** (where the
  heavy build runs, via `sbatch`).
- **GitHub access for one private submodule.** The sources are pulled in as *git
  submodules* (a submodule is just another git repo nested inside this one, pinned
  to an exact commit). All six LFRic source repos — `lfric_apps`, `lfric_core`,
  `casim`, `jules`, `socrates`, `ukca` — are **public** and clone anonymously over
  HTTPS, so no credentials are needed for them. The one exception is
  `stage1/vendor/mo-spack-packages`, which is still a private Met Office repo used
  by the Stage-1 build: it is on a `git@github.com:` URL and needs an SSH key registered
  with GitHub **and** authorised for the `MetOffice` organisation's SSO (GitHub →
  Settings → SSH keys → Configure SSO). If a `submodule update` fails, it is almost
  always that one.

---

## Stage 1 — build the environment

Stage 1 is self-contained in [`stage1/`](stage1/), which has its **own README with
the full procedure, diagrams and maintenance notes**:
**[`stage1/README.md`](stage1/README.md)**. The short version:

```bash
git clone <repo-url> lfric-env-isambard
cd lfric-env-isambard/stage1

pixi run submodules      # the pinned Spack + package repos (one-time)
pixi run concretize      # cheap login-node check that it still solves
pixi run fetch           # optional: pre-download every source
sbatch build.sbatch      # the build itself, ~1 h -> BUILD_OK
```

Everything installs **outside the repo**, under a versioned prefix
`$LFRIC_BASE/<version>` (default base `$PROJECTDIR/$USER/opt/Linux-aarch64`,
version read from `stage1/VERSION`). The version keeps independent builds in
distinct trees, so a rebuild never silently overwrites an environment others are
loading.

Unlike everything else in this repo, Stage 1 **requires pixi** — it is what
supplies the Python that Spack must run under (Spack 1.0 needs CPython
< 3.12). That requirement stops at the modulefile: nothing below needs pixi.

> **Why a compute node?** The login nodes cap the number of processes per user, so
> a full parallel build fails there with `fork: Resource temporarily unavailable`.
> `sbatch` runs it on a Grace compute node with enough cores and memory.

---

## Use the environment — the minimal-compile example (without pixi)

Once Stage 1 has finished, load the environment in any shell — no pixi, no Spack:

```bash
# Point at the base you built into (the default is shown):
export LFRIC_BASE="$PROJECTDIR/$USER/opt/$(uname -sm | tr ' ' -)"

module use "$LFRIC_BASE/modulefiles"
module avail lfric-env              # list every built version × variant
module load lfric-env/v2026.08.18/cray     # or: .../v2026.08.18/spack
rose --version; cylc --version; psyclone --version
```

The modulefiles live in ONE shared tree (`$LFRIC_BASE/modulefiles`) keyed by
`lfric-env/<version>/<variant>`, so `module avail lfric-env` shows every build —
pick the version you want. Expected (exact versions track the pinned sources):

```
rose 2.4.2
cylc 8.4.2
PSyclone version: 3.3.1
```

The modulefile carries absolute paths and its logic is snapshotted next to it, so
loading, compiling and running keep working even if this repo moves or is deleted.
(One qualification: `spack` commands against the loaded environment still read its
manifest, which `include:`s `stage1/spack-env/common.yaml` — so *those* need the
repo readable. Compiling and running do not.) Loading one variant/version swaps
out the other; bare `module load lfric-env` resolves to the most-recently-built
version's `cray`, and `module load lfric-env/<version>` to that version's `cray`.

### Optional: configure cylc (only if you will run rose/cylc suites)

This writes a run directory + an `isambard3` Slurm platform into `~/.cylc`. It is
opt-in (building the environment never touches your home directory):

```bash
bash scripts/setup-cylc.sh
```

### Optional: compile the `lfric_atm` example

A worked example of building a science target on the environment. It needs the
LFRic source and physics submodules — all public, no credentials:

```bash
git submodule update --init --jobs 4 -- \
  vendor/lfric_apps vendor/lfric_core \
  vendor/physics/casim vendor/physics/jules vendor/physics/socrates vendor/physics/ukca

sbatch examples/minimal-compile/build.sbatch                                  # cray
sbatch --export=ALL,LFRIC_STACK=spack examples/minimal-compile/build.sbatch   # spack
```

> Build one variant at a time — both compile in the same lfric_apps working tree,
> so don't run the two `lfric-atm` jobs concurrently. A successful run ends with
> `LFRIC_ATM_OK`.

A successful run ends with `LFRIC_ATM_OK`. See
[`examples/minimal-compile/README.md`](examples/minimal-compile/README.md) for how to adapt it
for your own suite.

---

## Run your own science suite (business as usual)

Already have your own LFRic Rose/Cylc suite? You do **not** need anything under
`examples/` to run it against this environment — those directories are integration
tests and adaptation templates, not a required layer. Point your own suite at the
built environment the way you would at any prebuilt toolchain: **load the module,
then let your suite inherit the toolchain from it.**

1. **Build Stage 1 once** (above) and `module load lfric-env/<version>/<variant>`
   wherever your suite activates its environment — for a Rose/Cylc suite that is a
   task `env-script`/`pre-script`, or an `ACTIVATE_ENV`-style script the tasks
   source.

2. **Inherit the compiler — don't hard-code it.** That single `module load` already
   exports the whole toolchain for the variant you loaded; you configure none of it:

   | The module sets | on `cray` | on `spack` |
   |-----------------|-----------|------------|
   | `FC`, `LDMPI` | `ftn` | the view's `mpif90` |
   | `CXX` | `CC` | the view's `mpic++` |
   | Cray PE modules | `PrgEnv-gnu` + Cray HDF5/netCDF **loaded** | *(none — self-contained)* |
   | `FFLAGS` | `-I<view>/include` *(prepended)* | same |
   | `LDFLAGS` | `-L<view>/lib{,64}` + `-rpath` + shumlib *(prepended)* | same |

   So in your suite's environment, **refer to those** instead of naming a literal
   compiler:

   ```ini
   # flow.cylc [[[environment]]] / rose-app.conf [env] — inherit from the module
   FC = $FC
   LDMPI = $LDMPI
   # CXX likewise if your suite sets it; otherwise the module's value is used as-is
   ```

   The one thing to watch: if your suite currently **hard-codes** a compiler — the
   upstream Met Office EX suites ship `FC = mpif90` / `LDMPI = mpif90` — that literal
   overrides the module's `ftn` and breaks the build on the `cray` env. Change it to
   `$FC` / `$LDMPI`. If your suite doesn't set `FC` at all, there is nothing to do:
   it already inherits the module's.

3. **You don't wire include/lib paths by hand.** The module puts the view's headers
   on `FFLAGS` and its libraries (plus shumlib) on `LDFLAGS`, **prepended** to any
   existing value. As long as your build chain *appends* its own flags rather than
   overwriting these — LFRic's Makefiles do — XIOS/HDF5/netCDF/shumlib are found with
   no extra `-I`/`-L` from you.

That is the entire contract: **`module load` + inherit `FC`/`LDMPI`.** Everything the
Stage-1 build knows about the Cray toolchain lives in the modulefile, so your suite
stays decoupled from how the environment was built. The science-suite examples under
[`examples/science-suites/`](examples/science-suites/) are exactly this pattern wired
into real suites — `site/activate-env.sh` (a thin module-load activator) and each
`u-*/flow.cylc` (`FC = $FC`) — so copy from them if it helps.

---

## Using pixi instead (optional)

Stage 1 requires pixi and documents its own tasks in
[`stage1/README.md`](stage1/README.md). For the **examples**, pixi is purely a
convenience — each task below wraps the script the sections above already use,
and it auto-loads the built module on every `pixi run`:

```bash
pixi run init-sources       # = the lfric_apps/lfric_core `git submodule update`
pixi run init-physics       # = the physics `git submodule update`
pixi run init-suites        # = the u-dr932 suite submodule
pixi run build-lfric-atm    # = examples/minimal-compile/build.sh
pixi run run-suite u-dr932  # = examples/science-suites/run-suite.sh
pixi run setup-cylc         # = scripts/setup-cylc.sh
pixi run activate           # report rose / cylc / psyclone versions
```

Inside pixi you can skip the explicit `module load`: after a build, every
`pixi run …` / `pixi shell` auto-loads the `LFRIC_STACK` variant, so
`pixi run rose --version` works directly.

---

## Configuration

Stage 1's configuration is one file — [`stage1/env.sh`](stage1/env.sh) — which is
also where the defaults below are set. The examples read only the last few.

| Variable | Default | What it controls |
|----------|---------|------------------|
| `LFRIC_STACK` | `cray` | Dependency variant: `cray` or `spack`. |
| `LFRIC_ENV_VERSION` | contents of `stage1/VERSION` (e.g. `v2026.08.18`) | **Environment version** (CalVer). Selects the versioned install prefix `$LFRIC_BASE/<version>` and the module name `lfric-env/<version>/<variant>`. Bump it by editing `stage1/VERSION`. Distinct from any LFRic apps/core version. The root `VERSION` must be kept in step — it is what the examples use to name the module they load. |
| `LFRIC_BASE` | `$PROJECTDIR/$USER/opt/<arch>` | The per-arch container, shared across versions. The shared modulefiles tree (`$LFRIC_BASE/modulefiles`) and the source/misc download caches sit here and are version-independent. Outside the repo. |
| `LFRIC_PREFIX` | `$LFRIC_BASE/<version>` | The versioned install: the Spack install tree, and the per-variant environment + view. Derived, not set. |
| `LFRIC_WORKING_DIR` | `$LOCALDIR/lfric-build-<variant>` | **Transient** Spack build/compile scratch, on node-local NVMe so the build stays off the shared Lustre. Safe to delete anytime. |
| `PROJECTDIR`, `LOCALDIR` | *(required)* | Site paths. Stage 1 checks them rather than guessing — a wrong guess installs gigabytes in the wrong filesystem. |
| `SPACK_JOBS` | `$SLURM_CPUS_PER_TASK` | Parallel build jobs (Stage 1). |
| `MAKE_JOBS` | `$SLURM_CPUS_PER_TASK` | Parallel make jobs (minimal-compile example). |
| `FETCH_JOBS` | `4` | Concurrency cap for the optional login-node pre-fetch; kept small for the login node's process limit. |

The versioned prefix is what makes the examples repo-independent: the build records
absolute paths into it, so once built you can move or delete the repo and
`module load` still works. To publish a rebuilt environment without disturbing the
one already in use, edit `stage1/VERSION` (and the root `VERSION` to match), commit,
then rebuild — the new build lands in a fresh `$LFRIC_BASE/<version>` and shows up
alongside the old one in `module avail lfric-env`.

## Cleaning up

There is no clean task — removal is a plain `rm`. To remove **one** built version,
delete its versioned prefix; to remove **all** versions, delete the base:

```bash
rm -rf "$LFRIC_BASE/$(cat stage1/VERSION)"   # just this version's install tree + env
rm -rf "$LFRIC_BASE"                         # ALL versions + shared modulefiles/caches
```

The transient stage (`$LFRIC_WORKING_DIR`, on node-local disk) is disposable and
generally cleared with the node; delete it directly if you want it gone sooner.

## Troubleshooting

- **`submodule update` fails / "Permission denied (publickey)".** This is
  `stage1/vendor/mo-spack-packages`, the one private submodule: your SSH key is
  not authorised for Met Office SSO (see [Prerequisites](#prerequisites)). The six
  LFRic source submodules are public and clone anonymously over HTTPS.
- **`fork: Resource temporarily unavailable` during a build.** You are building on
  a login node — submit `stage1/build.sbatch` to a compute node instead.
- **`Killed signal terminated program cc1plus` (out of memory).** Give the job
  more memory; the sbatch scripts already request a node's full per-core share. See
  the memory note in [`MAINTAINER.md`](MAINTAINER.md).
- **`Unable to clone XIOS …` / a source download fails mid-build.** Usually a
  transient source-host blip. Re-running resumes from the cache; to avoid it
  entirely, pre-fetch on the login node first (`pixi run fetch` in `stage1/`).

## More documentation

- [`stage1/README.md`](stage1/README.md) — **building the environment**: the whole
  procedure, what every file is for, and how to change it safely.
- [`MAINTAINER.md`](MAINTAINER.md) — how the examples work inside, and how to
  maintain them (patches, bumping pinned versions, tuning).
- [`examples/minimal-compile/README.md`](examples/minimal-compile/README.md) — the
  minimal-compile example and how to adapt it.
- [`examples/science-suites/README.md`](examples/science-suites/README.md) — the
  science-suite examples: running real Rose/Cylc LFRic suites on the built env.
- [`CLAUDE.md`](CLAUDE.md) — orientation for AI coding agents working in this repo.
