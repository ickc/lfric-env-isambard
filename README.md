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
  pinned sources ─▶ Spack builds everything ─▶ a loadable module under $LFRIC_PREFIX

Example: minimal-compile  —  USE the env to compile a target   (lightweight)
  module load lfric-env/<version>/<variant> ─▶ rose / cylc / psyclone / spack …
                                   └▶ compile lfric_atm (examples/minimal-compile/)

Example: science-suites   —  RUN a real suite   (cylc on the login node ─▶ Slurm)
  cylc vip a Rose/Cylc LFRic suite (examples/science-suites/u-*/) on the built env
```

- **Stage 1** is the reproducible core of this repo — the one true prerequisite. It
  needs the repo + a Python in [3.7, 3.12). It produces a self-contained Lmod
  modulefile under `$LFRIC_PREFIX`. (We keep the name "Stage 1"; the examples below
  build on it rather than following it as stages.)
- **The minimal-compile example** (`examples/minimal-compile/`) is the smallest thing
  you do *with* the built env: compile the `lfric_atm` target, no science run. It needs
  only the modulefile — no Spack, no pixi, and the repo can even have moved or been
  deleted. Adapt it for your own science target.
- **The science-suite examples** (`examples/science-suites/`) run real Rose/Cylc suites
  on the built env the way scientists do — `cylc` schedules the suite and submits to
  Slurm; each suite declares its LFRic source refs in `dependencies.yaml` and compiles
  its own `lfric_atm` (e.g. `pixi run run-suite u-dr932`, on the default `cray` env).

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
  `vendor/mo-spack-packages`, which is still a private Met Office repo used by the
  Stage-1 build: it is on a `git@github.com:` URL and needs an SSH key registered
  with GitHub **and** authorised for the `MetOffice` organisation's SSO (GitHub →
  Settings → SSH keys → Configure SSO). If a `submodule update` fails, it is almost
  always that one.

---

## Stage 1 — build the environment (without pixi)

Run this **session** from a login node. The two `git submodule` lines fetch only
the Stage‑1 (core) sources; the heavy build itself runs on a compute node.

```bash
# 1. Clone the repo and fetch the Stage-1 (core) submodules.
git clone <repo-url> lfric-env-isambard
cd lfric-env-isambard
git submodule update --init --recursive --jobs 4 -- \
  vendor/spack vendor/spack-packages vendor/lfric_apps vendor/lfric_core vendor/mo-spack-packages

# 2. Build on a compute node. The config block at the top of scripts/build.sbatch
#    sets WHERE to build (edit it if your paths differ) — see "Configuration".
sbatch scripts/build.sbatch                                  # cray variant (default)
sbatch --export=ALL,LFRIC_STACK=spack scripts/build.sbatch   # spack variant
```

The job writes its log to `logs/build-<jobid>.out`; a successful run ends with
`BUILD_OK`. From scratch the build takes roughly 1–3 hours; re-runs are incremental
(Spack skips already-built packages). The two variants **share one install tree**,
so building the second one only rebuilds the MPI-dependent part.

Everything installs under a **versioned** prefix `$LFRIC_PREFIX/<version>` (default
base `$PROJECTDIR/$USER/opt/Linux-aarch64`, version read from the repo's `VERSION`
file, e.g. `v2026.07.21`), which is **outside the repo** — see
[Configuration](#configuration). The version keeps independent builds in distinct
trees, so a rebuild never silently overwrites an environment others are loading.

> **Why a compute node?** The login nodes cap the number of processes per user, so
> a full parallel build fails there with `fork: Resource temporarily unavailable`.
> `sbatch` runs it on a Grace compute node with enough cores and memory.

### Optional: pre-fetch the sources on the login node

Spack downloads each package's source the first time it builds it — including a
git clone of **XIOS** from `gitlab.in2p3.fr`. To do all the network + disk I/O up
front (and make the compute-node build robust to an intermittent source-host
outage), pre-fetch everything on the **login node** first:

```bash
bash scripts/fetch.sh                          # cray variant (default)
LFRIC_STACK=spack bash scripts/fetch.sh        # spack variant
```

This clones any missing Stage-1 submodules, concretizes the variant, then
downloads every source into the shared cache under `$LFRIC_PREFIX`. The subsequent
`sbatch` build reuses that cache and fetches nothing. Like the build, it needs a
Python in [3.7, 3.12) (`module load cray-python/3.11.7`, or use `pixi run fetch`).
Concurrency is capped for the login node's process limit (`FETCH_JOBS`, default 4).

---

## Use the environment — the minimal-compile example (without pixi)

Once Stage 1 has finished, load the environment in any shell — no pixi, no Spack:

```bash
# Point at the base you built into (the default is shown):
export LFRIC_PREFIX="$PROJECTDIR/$USER/opt/$(uname -sm | tr ' ' -)"

module use "$LFRIC_PREFIX/modulefiles"
module avail lfric-env              # list every built version × variant
module load lfric-env/v2026.07.21/cray     # or: .../v2026.07.21/spack
rose --version; cylc --version; psyclone --version
```

The modulefiles live in ONE shared tree (`$LFRIC_PREFIX/modulefiles`) keyed by
`lfric-env/<version>/<variant>`, so `module avail lfric-env` shows every build —
pick the version you want. Expected (exact versions track the pinned sources):

```
rose 2.4.2
cylc 8.4.2
PSyclone version: 3.3.1
```

The modulefile carries absolute paths, so this keeps working even if the repo
moves or is deleted. Loading one variant/version swaps out the other; bare
`module load lfric-env` resolves to the most-recently-built version's `cray`, and
`module load lfric-env/<version>` to that version's `cray`.

### Optional: configure cylc (only if you will run rose/cylc suites)

This writes a run directory + an `isambard3` Slurm platform into `~/.cylc`. It is
opt-in (building the environment never touches your home directory):

```bash
bash scripts/setup-cylc.sh
```

### Optional: compile the `lfric_atm` example

A worked example of building a science target on the environment. It needs the
**Stage‑2 physics submodules** (private Met Office repos — same SSH access as above):

```bash
git submodule update --init --jobs 4 -- \
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

[pixi](https://pixi.sh) is **only a convenience for Stage 1**: it supplies the
Python that runs Spack and gives you task shortcuts, and it auto-loads the built
module on every `pixi run`. Nothing below is required — each task just wraps the
script the no-pixi sections above already use.

```bash
pixi run submodule-init     # = the Stage-1 `git submodule update` above
pixi run fetch              # = scripts/fetch.sh (cray)   — pre-fetch sources on a login node
pixi run fetch-spack        # = scripts/fetch.sh (spack)
pixi run concretize         # = scripts/concretize.sh (cray)  — solve only (cheap login-node check)
pixi run concretize-spack   # = scripts/concretize.sh (spack)
pixi run build              # = scripts/build.sh (cray)   — run on a compute node
pixi run build-spack        # = scripts/build.sh (spack)
pixi run activate           # report rose / cylc / psyclone versions

# minimal-compile example:
pixi run init-physics       # = the physics `git submodule update` above
pixi run build-lfric-atm    # = examples/minimal-compile/build.sh
pixi run setup-cylc         # = scripts/setup-cylc.sh
```

The heavy build still needs a compute node: either submit `scripts/build.sbatch`
(its last line shows how to switch it to `exec pixi run build`), or use `pixi run
concretize` interactively for a quick solve-only check before submitting.

Inside pixi you can skip the explicit `module load`: after a build, every
`pixi run …` / `pixi shell` auto-loads the `LFRIC_STACK` variant, so
`pixi run rose --version` / `pixi run spack find` work directly.

---

## Configuration

The build is configured entirely through a few environment variables. The sbatch
scripts set them explicitly in a config block at the top — read or edit that block
to see/change exactly where things go.

| Variable | Default | What it controls |
|----------|---------|------------------|
| `LFRIC_STACK` | `cray` | Dependency variant: `cray` or `spack`. |
| `LFRIC_ENV_VERSION` | contents of `./VERSION` (e.g. `v2026.07.21`) | **Environment version** (CalVer). Selects the versioned install prefix `$LFRIC_PREFIX/<version>` and the module name `lfric-env/<version>/<variant>`. Read from the committed `VERSION` file; bump it with `bash scripts/bump-env-version.sh` (`pixi run bump-env-version`). Distinct from any LFRic apps/core version. |
| `LFRIC_PREFIX` | `$PROJECTDIR/$USER/opt/<arch>` | **Base** install location (the per-arch container, shared across versions). The actual install goes into the **versioned** prefix `$LFRIC_PREFIX/$LFRIC_ENV_VERSION`: the Spack install tree, the per-variant environment + view. The shared modulefiles tree (`$LFRIC_PREFIX/modulefiles`) and the source/misc download caches sit at this base and are version-independent. Outside the repo. |
| `LFRIC_WORKING_DIR` | `$LFRIC_PREFIX/<version>/stage` | **Transient** Spack build/compile scratch. On a compute node the sbatch points this at node‑local NVMe (`$LOCALDIR/…`) so the build stays off the shared Lustre. Safe to delete anytime. |
| `SPACK_JOBS` | `$SLURM_CPUS_PER_TASK` | Parallel build jobs (Stage 1). |
| `MAKE_JOBS` | `$SLURM_CPUS_PER_TASK` | Parallel make jobs (minimal-compile example). |
| `FETCH_JOBS` | `4` | Concurrency cap for the optional login-node pre-fetch (`scripts/fetch.sh`); kept small for the login node's process limit. |

The versioned prefix is what makes the minimal-compile example repo-independent: the build records absolute
paths into it, so once built you can move or delete the repo and `module load`
still works. To publish a rebuilt environment without disturbing the one already in
use, `pixi run bump-env-version` (or `bash scripts/bump-env-version.sh`), commit
`VERSION`, then rebuild — the new build lands in a fresh `$LFRIC_PREFIX/<version>`
and shows up alongside the old one in `module avail lfric-env`.

## Cleaning up

There is no clean task — removal is a plain `rm`. To remove **one** built version,
delete its versioned prefix; to remove **all** versions, delete the base:

```bash
rm -rf "$LFRIC_PREFIX/$(cat VERSION)"   # just this version's install tree + env
rm -rf "$LFRIC_PREFIX"                  # ALL versions + the shared modulefiles/caches
```

The transient stage (`$LFRIC_WORKING_DIR`, on node-local disk) is disposable and
generally cleared with the node; delete it directly if you want it gone sooner.

## Troubleshooting

- **`submodule update` fails / "Permission denied (publickey)".** This is
  `vendor/mo-spack-packages`, the one remaining private submodule: your SSH key is
  not authorised for Met Office SSO (see [Prerequisites](#prerequisites)). The six
  LFRic source submodules are public and clone anonymously over HTTPS.
- **`fork: Resource temporarily unavailable` during a build.** You are building on
  a login node — submit `scripts/build.sbatch` to a compute node instead.
- **`Killed signal terminated program cc1plus` (out of memory).** Give the job
  more memory; the sbatch scripts already request a node's full per-core share. See
  the memory note in [`MAINTAINER.md`](MAINTAINER.md).
- **`Unable to clone XIOS …` / a source download fails mid-build.** Usually a
  transient source-host blip. Re-running resumes from the cache; to avoid it
  entirely, pre-fetch on the login node first (see
  [Optional: pre-fetch the sources](#optional-pre-fetch-the-sources-on-the-login-node)).

## More documentation

- [`MAINTAINER.md`](MAINTAINER.md) — how it works inside, and how to maintain it
  (variants, patches, bumping pinned versions, the modulefile, tuning).
- [`examples/minimal-compile/README.md`](examples/minimal-compile/README.md) — the
  minimal-compile example and how to adapt it.
- [`examples/science-suites/README.md`](examples/science-suites/README.md) — the
  science-suite examples: running real Rose/Cylc LFRic suites on the built env.
- [`CLAUDE.md`](CLAUDE.md) — orientation for AI coding agents working in this repo.
