# lfric-env-isambard

A reproducible build of the **LFRic Apps Spack environment** for the
**Isambard 3** supercomputer (GCC 14.3, Grace/aarch64). It turns a set of pinned
source repositories into a ready-to-use environment you load with one `module`
command — giving you `rose`, `cylc`, `psyclone`, `xios` and the full LFRic
dependency stack, without you having to drive Spack yourself.

You do **not** need to know Spack or [pixi](https://pixi.sh) to use this repo.
The steps below use plain `git`, `module` and `sbatch`. A pixi shortcut is
offered separately at the end for those who want it.

## The two stages

```
Stage 1  —  BUILD the environment            (run once; heavy; on a compute node)
  pinned sources ─▶ Spack builds everything ─▶ a loadable module under $LFRIC_PREFIX

Stage 2  —  USE the environment              (just `module load`; lightweight)
  module load lfric-env/<variant> ─▶ rose / cylc / psyclone / spack …
                                   └▶ compile a science suite (examples/lfric-atm/)
```

- **Stage 1** is the reproducible core of this repo. It needs the repo + a Python
  in [3.7, 3.12). It produces a self-contained Lmod modulefile under `$LFRIC_PREFIX`.
- **Stage 2** is everything you do *with* the built environment. It needs only the
  modulefile — no Spack, no pixi, and the repo can even have moved or been deleted.
  Compiling the `lfric_atm` example (`examples/lfric-atm/`) is one worked example
  of Stage 2; adapt it for your own science suite.

There are **two dependency variants**, chosen with `LFRIC_STACK`:

| `LFRIC_STACK` | MPI + parallel I/O | Use for |
|---------------|--------------------|---------|
| `cray` (default) | system **cray-mpich** + Cray parallel HDF5/netCDF | production runs on Isambard |
| `spack` | **mpich** + HDF5/netCDF **built from source** | portability / CI / comparison |

So there are four things you can build: {Stage 1, Stage 2 example} × {`cray`, `spack`}.

## Prerequisites

- **An Isambard 3 account**, and the basics of using it: the difference between a
  **login node** (where you clone + submit jobs) and a **compute node** (where the
  heavy build runs, via `sbatch`).
- **An SSH key authorised for Met Office SSO.** Several source repositories are
  private Met Office repos pulled in as *git submodules* (a submodule is just
  another git repo nested inside this one, pinned to an exact commit). Cloning
  them needs an SSH key registered with GitHub **and** authorised for the
  `MetOffice` organisation's SSO (GitHub → Settings → SSH keys → Configure SSO),
  or an HTTPS credential helper (`gh auth setup-git`). If a `submodule update`
  fails, this is almost always why.

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

Everything installs under **`$LFRIC_PREFIX`** (default
`$PROJECTDIR/$USER/opt/Linux-aarch64`), which is **outside the repo** — see
[Configuration](#configuration).

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
downloads every source into the cache under `$LFRIC_PREFIX`. The subsequent
`sbatch` build reuses that cache and fetches nothing. Like the build, it needs a
Python in [3.7, 3.12) (`module load cray-python/3.11.7`, or use `pixi run fetch`).
Concurrency is capped for the login node's process limit (`FETCH_JOBS`, default 4).

---

## Stage 2 — use the environment (without pixi)

Once Stage 1 has finished, load the environment in any shell — no pixi, no Spack:

```bash
# Point at the prefix you built into (the default is shown):
export LFRIC_PREFIX="$PROJECTDIR/$USER/opt/$(uname -sm | tr ' ' -)"

module use "$LFRIC_PREFIX/modulefiles"
module load lfric-env/cray          # or: module load lfric-env/spack
rose --version; cylc --version; psyclone --version
```

Expected (exact versions track the pinned sources):

```
rose 2.4.2
cylc 8.4.2
PSyclone version: 3.2.2
```

The modulefile carries absolute paths, so this keeps working even if the repo
moves or is deleted. Loading one variant swaps out the other; bare
`module load lfric-env` resolves to the default (`cray`).

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

sbatch examples/lfric-atm/build.sbatch                                  # cray
sbatch --export=ALL,LFRIC_STACK=spack examples/lfric-atm/build.sbatch   # spack
```

> Build one variant at a time — both compile in the same lfric_apps working tree,
> so don't run the two `lfric-atm` jobs concurrently. A successful run ends with
> `LFRIC_ATM_OK`.

A successful run ends with `LFRIC_ATM_OK`. See
[`examples/lfric-atm/README.md`](examples/lfric-atm/README.md) for how to adapt it
for your own suite.

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

# Stage 2:
pixi run init-physics       # = the physics `git submodule update` above
pixi run build-lfric-atm    # = examples/lfric-atm/build.sh
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
| `LFRIC_PREFIX` | `$PROJECTDIR/$USER/opt/<arch>` | **Persistent** install location: the Spack install tree, the per-variant environment + view, the modulefiles and caches. Outside the repo; shared by both variants. |
| `LFRIC_WORKING_DIR` | `$LFRIC_PREFIX/stage` | **Transient** Spack build/compile scratch. On a compute node the sbatch points this at node‑local NVMe (`$LOCALDIR/…`) so the build stays off the shared Lustre. Safe to delete anytime. |
| `SPACK_JOBS` | `$SLURM_CPUS_PER_TASK` | Parallel build jobs (Stage 1). |
| `MAKE_JOBS` | `$SLURM_CPUS_PER_TASK` | Parallel make jobs (Stage 2 example). |
| `FETCH_JOBS` | `4` | Concurrency cap for the optional login-node pre-fetch (`scripts/fetch.sh`); kept small for the login node's process limit. |

`LFRIC_PREFIX` is what makes Stage 2 repo-independent: the build records absolute
paths into it, so once built you can move or delete the repo and `module load`
still works.

## Cleaning up

There is no clean task — removal is a plain `rm`. To remove **all** build output,
delete your prefix:

```bash
rm -rf "$LFRIC_PREFIX"          # the whole install (tree, env, view, modulefiles, caches)
```

The transient stage (`$LFRIC_WORKING_DIR`, on node-local disk) is disposable and
generally cleared with the node; delete it directly if you want it gone sooner.

## Troubleshooting

- **`submodule update` fails / "Permission denied (publickey)".** Your SSH key is
  not authorised for Met Office SSO (see [Prerequisites](#prerequisites)).
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
- [`examples/lfric-atm/README.md`](examples/lfric-atm/README.md) — the Stage-2
  example and how to adapt it.
- [`CLAUDE.md`](CLAUDE.md) — orientation for AI coding agents working in this repo.
