# The science-suite examples — run real LFRic suites (Rose/Cylc)

This directory holds the **science-suite examples**: running real LFRic
**Rose/Cylc science suites** on the environment that Stage 1 built. Scientists run
LFRic this way — `cylc` schedules the suite's task graph (extract → build → mesh →
run) and submits each task to Slurm; `rose` materialises each task's namelist
config. So these examples run the suites *that* way, rather than reinventing it.

> The reproducible **core** of this repo is the environment (Stage 1,
> `scripts/build.sh`). These suites are **not** that core — they are things you do
> *with* it. Treat them as templates to copy and adapt. They are ported from the
> upstream [Isambard3-LFRic-Env-Science-Suites](https://github.com/UniExeterRSE/Isambard3-LFRic-Env-Science-Suites).

The environment Stage 1 builds already ships `cylc`, `rose` and `rose_picker` in
its view (dependencies of `lfric-apps-isambard`), so there is nothing extra to
install — `run-suite.sh` activates the env and the suite tasks use that same
`cylc`/`rose`.

## The contract: the module is the interface, the rest is business as usual

**Stage 1 and its `module load` are the whole contract.** `module load
lfric-env/<version>/<variant>` exports the toolchain — `FC`/`CXX`/`LDMPI`/`FPP`, the
Cray PE modules, the view's `FFLAGS`/`LDFLAGS` for XIOS/HDF5/netCDF/shumlib, and
`rose`/`cylc`/`psyclone` on `PATH`. A suite **consumes** that and re-derives none of
it: `FC = $FC` in `[[BUILD]]` is the whole integration. That is the line these
examples defend — if a suite has to know anything else about how the environment was
built, the modulefile is wrong, not the suite.

**On the other side of that line, a scientist should be able to work exactly as they
already do.** These are Met Office Rose/Cylc suites and their users have Met Office
habits; every habit we break is friction that gets this environment rejected. So the
examples keep the upstream mechanisms even where a bespoke one would be tidier for
us:

- **Sources stay `dependencies.yaml` + `merge_sources.py`.** Changing what gets
  built — a different tag, your own fork, a fork merged onto a tag — is the same edit
  you would make at the Met Office, and the extract clones it from github at run time
  like it does there. It is *offered* offline (`USE_MIRRORS=true` against this repo's
  vendored submodules, `vendor/mirrors/`), not imposed.
- **The launcher stays the Met Office `launch-exe`** out of the extracted source
  tree, wherever its own `RUN_METHOD=srun` path already does the right thing.
- **The suite still detects its own machine**, still carries its other platforms'
  branches, and still runs unmodified on them.
- **Tasks still run where the suite says they run** — the extract is a Slurm job on a
  compute node, as upstream has it, not something pre-fetched on the login node on
  the suite's behalf. Isambard 3's compute nodes have outbound network; there is no
  reason to invent a staging dance around a restriction that does not exist. (The
  *environment build* is a different matter — Stage 1 is reproducible and offline by
  design. That invariant is Stage 1's, and it does not propagate into the suites.)

What we do change, we change for a stated reason, and mark in place:

- **things the platform requires** — `srun` instead of `mpiexec` (there is no
  `mpiexec` in the cray environment), the `isambard3` Cylc platform, sourcing the
  module instead of another site's software stack;
- **things that are wrong here and would silently cost you** — above all the Slurm
  placement directives (see below), which is what made a suite 3–4× slower than
  Monsoon;
- **version alignment** — a suite written for vn3.1 needs its namelists upgraded to
  the vn3.2 the environment builds, done with `rose app-upgrade`, the native tool.

Each suite's own `README.md` is the itemised list of its changes, and each change is
commented `[isambard3]` at the point it applies. If you are reviewing whether this
environment is worth adopting, those two things are the diff you are being asked to
accept.

## The suites

| Suite | Science case | Status on this env |
|-------|--------------|--------------------|
| **u-dr932** | GungHo Shallow/Deep Hot Jupiter temperature forcing (C48 multigrid, idealised) | ✅ **builds + runs end-to-end** — self-contained (radiation off, analytic init; no external data). Validated on the **cray** environment (Grace node, 24 ranks single-node; `lfric_atm` ran 72 steps to completion), re-validated on the `2026.07.1` / vn3.2 stack. Needs `patches/31-lfric_apps-slow-physics-mphys-field-patch.sh`: vn3.2 stopped creating the UM-physics fields for a forcing-only config while `slow_physics` still fetched `dtheta_mphys`. |
| **u-dn704** | LFRic Atm NWP GAL9 @ C12 | ✅ **builds + runs end-to-end, multi-node** on the **cray** environment — 24 model ranks + 1 dedicated XIOS server across 2 nodes over **Slingshot (cxi)**; the XIOS server wrote the native-UGRID parallel-HDF5 output (`lfric_gal_diagnostics.nc` ~62 MB); re-validated on the `2026.07.1` / vn3.2 stack (62 MB, S144 to completion). The NWP ancils, start dump and `um_aux` ctldata are **staged on Isambard 3** at the default `BIG_DATA_DIR=/projects/u35v/sw/lfricdata` and read offline at run time (GA9 spectra come from the vendored socrates — no MO `um_aux` clone, no SSO). |
| **u-dt000** | LFRic Atm Uranus/Neptune temperature forcing | ⚠️ **builds + meshes**; the run is **blocked on a missing upstream LFRic fork**, not config or version. Its cray run config is ported (mirrors dn704: dedicated XIOS server via `srun`, 24-rank placeholder — was 108) and **validates**. Re-confirmed on the `2026.07.1` / vn3.2 stack: extract, both mesh tasks and `build_lfric_atm` all succeed, then the model reads its namelists and aborts at `Cannot match namelist object name held_suarez_sigma_b` / `STOP 1` — the same blocker as before, untouched by the version bump. The suite's core science is `theta_forcing='ice_giants_obs_like'` in `namelist:external_forcing`, **absent from both this repo's vendored `2026.07.1` (vn3.2) AND the suite's own declared mainline `lfric_apps@vn2.2`** (verified by extracting both: no `ice_giants_obs_like`; `held_suarez_sigma_b` isn't a namelist field in either — `SIGMA_B=0.7` is a hardcoded `parameter`). The upstream suite's extract points only at MetOffice mainline vn2.2, which lacks this science, so the ice-giant forcing lives in an **unidentified fork the suite does not reference**. No namelist forward-port can fix this; running dt000's science needs that fork located + staged. See `PLAN.md`. |

### Version alignment (forward-porting suite configs)

This repo's vendored LFRic is **newer** (`2026.07.1` = apps vn3.2) than the upstream
suites pin (vn3.0 / vn2.2), and these examples build `lfric_atm` from the vendored
source (see below). So a suite's namelists must match **vn3.2**, not the version it
was written for. These are mechanical, non-science edits — e.g. u-dr932/u-dn704's
`finite_element` namelist gained `coord_space='Wchi'` and `coord_order_nonprime=1`
(required by vn3.1.1, absent in vn3.0). This is the legitimate adaptation: a
scientist running on *this* env writes vn3.2 configs. The deeper a suite's
version lag, the more such edits its run needs.

**Use `rose app-upgrade`, the native tool — on a config that is genuinely at the
version it claims.**

```bash
. examples/science-suites/site/activate-env.sh
export ROSE_META_PATH=$(find vendor/lfric_apps vendor/lfric_core -type d -name rose-meta | tr '\n' ':')
cd <suite>/app && rose app-upgrade -y -C lfric_atm vn3.2 && rose macro --validate
```

That is how u-dr932 was taken from vn3.1 to vn3.2: clean, in one command, including
the `jules_pftparm` migration into its indexed per-PFT form.

It is worth knowing why the earlier attempt concluded the opposite. Run against
*this repo's older copy* of the same suite, the `jules_pftparm` macro died with
`AttributeError: 'NoneType' object has no attribute 'split'` — because that copy had
already been hand-ported through vn3.0→vn3.1, and had `jules_pftparm` in the very
form the vn3.1→vn3.2 macro was trying to produce. **The tool was fine; the input was
a config that no longer matched its declared `meta=` version.** The lesson is to
upgrade from an honest starting point — the upstream suite at its own version —
rather than to hand-port and then upgrade.

(If you ever do have to reconstruct a change set by hand, the previous method is
still recorded in the git history of this file: derive it from the upstream
`version31_32.py` macros of exactly the rose-meta packages in `lfric_atm`'s
`import=` chain — 16 of them — and note that rose's `import=` uses continuation
lines, so a parser reading only the first line sees 3.)

Adding the *new* vn3.2 members matters as much as the renames: LFRic initialises
them to RMDI and then range-checks them, so a missing one is a hard abort, not a
default — u-dn704 died on `c_mass_sh, (-0.107E+10), has failed to pass any
defensive checks, [0.01:0.09]`. Supply the macro's default value.

There is a limit to forward-porting, though: it can only reshape *run config* for
science the model already implements. When a suite's science needs **code** that the
model lacks, no namelist edit can bridge the gap — that's a *source* / build-time
divergence. The clean way to express it is the upstream-native per-suite
`dependencies.yaml` (each LFRic-source repo with `source:`+`ref:`, which can even merge
a fork onto a tag); see `PLAN.md` for the offline-extract design. u-dt000 is the hard
case: its `ice_giants_obs_like` forcing is in **neither** the vendored `2026.07.1` (vn3.2) **nor**
its own declared mainline vn2.2 — it needs a fork the suite doesn't reference, which
must be located upstream first. See `PLAN.md`.

## How it works here (what was adapted)

Each suite is the upstream Rose/Cylc suite with three site-specific changes, so it
runs against *our* env on Isambard 3:

1. **Sources → the upstream extract, plus this repo's patch stack.** Each suite
   declares the LFRic-source refs it builds in a **`dependencies.yaml`** (the
   upstream shape: `lfric_apps`, `lfric_core`, `casim`, `jules`, `socrates`, `ukca`,
   each with `source:` + `ref:`), and the `extract` task runs the Met Office
   `merge_sources.py` over it exactly as upstream does — cloning each ref into the
   suite's `SOURCE_ROOT` on the compute node the task runs on. Editing
   `dependencies.yaml` is how you build different science; it is the same edit you
   would make anywhere else.

   Two site details. `site/patch-sources.sh` is appended to the extract command: it
   applies this repo's LFRic-source **patch stack** (`patches/*-lfric_*`, the same
   ones the env build and minimal-compile use, retargeted via `LFRIC_SRC_ROOT`) to
   the freshly cloned tree — without it the apps build re-clones its own science
   sources mid-compile. And `--mirror_loc` points at `vendor/mirrors/`, this repo's
   vendored submodules arranged in the Met Office `MetOffice/<repo>.git` mirror
   layout, so `USE_MIRRORS=true` gives a **fully offline** extract from refs already
   vendored. The default is `USE_TOKENS=true` — https clones from github, which need
   no token for these public repositories.

   > u-dn704 and u-dt000 have not been moved to this yet; they still use
   > `site/extract-sources.sh`, which materialises a ref offline from the vendored
   > submodules with `git archive`. It is a strict-offline equivalent of the
   > `USE_MIRRORS=true` path above, and will be retired when those two are next
   > re-validated.
2. **Env activation → our modulefile.** `site/activate-env.sh` (passed as the
   suite's `ACTIVATE_ENV`) is a **thin activator**: it `module load`s
   `lfric-env/<version>/$LFRIC_STACK`, and that one module supplies the whole
   toolchain (compiler wrappers + Cray PE modules + the view's `FFLAGS`/`LDFLAGS`).
   The script itself only initialises Lmod, preserves the source/target vars the
   suite owns, and adds the Lustre HDF5 file-locking workaround — the
   science-suite-example analogue of upstream's `env_lfric/activate.sh`.
3. **Cylc platform → Slurm.** `run-suite.sh` runs the repo's opt-in
   `scripts/setup-cylc.sh`, which writes the `isambard3` platform
   (`job runner = slurm`, on `localhost`) and a roomy `cylc-run` dir into
   `~/.cylc/flow/` (idempotent; the same setup `pixi run setup-cylc` does).

### Placement and MPI transport — the contract

A ported suite must **state where its ranks go**. This is not a tuning nicety; get it
wrong and the model is several times slower, which is how a suite ported to Isambard 3
outside this repo ended up 3–4× slower than Monsoon (investigated in full, with
measurements, in [`staging/dr932-mpi-scaling/`](../../staging/dr932-mpi-scaling/)).
Three rules, all visible in the suites here:

- **`RUN_METHOD = srun`, never `mpiexec`.** `srun` is what binds cray-mpich to
  Slingshot's `cxi` provider through the Cray PMI, and it pins one rank per core
  without being asked. Note the `cray` environment does not even ship an `mpiexec`.
  The **stock Met Office `launch-exe` already handles this** — its `RUN_METHOD=srun`
  path emits `srun <exe> <namelist>`, which is all a run with XIOS attached needs, so
  u-dr932 keeps upstream's `LAUNCH_SCRIPT`. `site/bin/launch-exe` is only needed for
  the **dedicated XIOS server** (u-dn704): the MO launcher wires that MPMD up under
  Hydra colon syntax only, and under `srun` it wants `--multi-prog` to put client and
  server in one `MPI_COMM_WORLD`.
- **The `lfric_atm` `[[[directives]]]` must carry `--nodes` *and*
  `--ntasks-per-node`, with `--mem=0`.** Given only `--ntasks` plus a per-CPU memory
  request, Slurm satisfies it out of whatever nodes have room: a 108-rank job that fits
  on one 144-core Grace node was observed spread over **9 to 32** nodes, with 1–13 ranks
  each. `--mem=0` takes the node's whole memory so a memory request can never cap
  ranks-per-node and fan the job out. On cray-mpich that scatter is survivable (measured
  at ~1.1× on the model, inside run-to-run noise) — it is when it combines with an MPI
  that falls back to TCP that it costs a factor of several, which is precisely why the
  two rules above travel together.
- **A Grace node is 144 cores** (2 sockets × 72), not the 128 the upstream suites
  assume. `LPPN`/`CORES_PER_NODE` are set to 144 here.
- **Ask for whole nodes (`--exclusive`).** `SelectType` is `select/cons_tres`
  (`CR_CORE_MEMORY`), so Slurm hands out *cores*, not machines: a task that takes 13 of
  a node's 144 cores leaves the other 131 for anyone. Over one 9-hour run, 1493 distinct
  jobs from other users touched the 32 nodes the scattered example was spread across.
  That co-tenancy is where the 5 h → 9 h spread on identical work came from, so
  exclusivity is what makes a timing reproducible, not just faster. Keep `--mem=0`
  alongside it — `--exclusive` gives all the *CPUs*, but memory still follows
  `DefMemPerCPU` (1024 MB × 144 = 144 GB of a 225 GB node).
- **Threads: these suites are pure MPI (`OMP_NUM_THREADS=1`, `--cpus-per-task=1`).**
  The binaries *are* OpenMP-linked (`libgomp`), so this is a live knob, not a rebuild —
  and worth knowing that at 108 ranks × 1 thread, 36 of a node's 144 cores sit idle.
  If you do raise it, three things move together or the run gets slower, not faster:
  `--cpus-per-task=N`, `OMP_NUM_THREADS=N` (it is hardcoded in each suite's
  `app/lfric_atm/rose-app.conf`, which overrides the task environment), and the
  binding. Under `srun` that means `--cpus-per-task=N` plus `OMP_PROC_BIND=close` /
  `OMP_PLACES=cores`; under Hydra, `-bind-to core:N` — plain `-bind-to core` pins the
  whole rank to *one* core and its N threads then fight over it. Rank/thread balance on
  LFRic is not something this repo has measured; treat it as an experiment to run, not
  a recommendation to follow.

The measured cost of getting this wrong, 108 ranks throughout (full table in the
staging README):

| | 8 B allreduce | 1 MiB pairwise | 64 KiB ring |
|---|---|---|---|
| scattered over 11 nodes, unpinned, from-source MPICH over TCP | 2494 µs | 0.70 GB/s | 1312 µs |
| one node, pinned, cray-mpich under `srun` | **5.2 µs** | **1682 GB/s** | **15.6 µs** |

Rank counts are worth a thought too: a cubed-sphere partition wants `6 × n²` ranks for
square subdomains — **24, 54, 96** all fit one node; 108 works but gives each rank a
16×8 patch instead of a square one.

## Prerequisites

- **Stage 1 built** for the variant you want (`scripts/build.sbatch`). Run the
  suites on the **`cray`** environment (the default): on Isambard 3 only
  cray-mpich + Slingshot + `srun` give RDMA over the interconnect and multi-node
  scaling — the `spack` variant is a single-node/TCP portable fallback. The
  suites' build **inherits** the compiler from the loaded module (`flow.cylc` does
  `FC = $FC` / `LDMPI = $LDMPI`), which resolves to Cray `ftn`/`CC` on `cray` or the
  view's `mpif90`/`mpic++` on `spack` — so switching variant needs no suite edit.
- **Physics submodules initialised** (as for the minimal-compile example):
  `git submodule update --init --jobs 4 -- vendor/physics/{casim,jules,socrates,ukca}`
  (or `pixi run init-physics`).

## Run it

Everything below happens on a **login node**. The Cylc scheduler is a long-lived
process that lives there and submits each task to Slurm itself, so **nothing here is
wrapped in `sbatch`** — `sbatch`-ing the scheduler is the classic mistake.

```bash
bash examples/science-suites/run-suite.sh u-dr932   # cray environment (the default)
```

That is the whole launch. `run-suite.sh` is a convenience wrapper, not a new
mechanism — it does three things you could do by hand:

```bash
# 1. put the built environment on PATH (rose/cylc/psyclone come from its view)
. examples/science-suites/site/activate-env.sh

# 2. write the `isambard3` Slurm platform + a roomy cylc-run dir into ~/.cylc/flow
bash scripts/setup-cylc.sh

# 3. validate, install and play, telling the suite which environment to load
cylc vip examples/science-suites/u-dr932 --workflow-name u-dr932 \
  -S "REPO_ROOT='$PWD'" \
  -S "LFRIC_STACK='cray'" \
  -S "LFRIC_PREFIX='<the PREFIX Stage 1 installed into, unversioned>'" \
  -S "LFRIC_ENV_VERSION='<the version from ./VERSION>'" \
  -S "ACTIVATE_ENV='$PWD/examples/science-suites/site/activate-env.sh'"
```

Anything you pass to `run-suite.sh` after the suite name goes straight to `cylc vip`,
so suite settings are overridden the usual way — `-S EXPT_RUNLEN=P1200D`,
`-S TOTAL_RANKS_REQ=54`, `--pause`, and so on.

Watch and drive it with plain Cylc:

```bash
cylc tui u-dr932                       # interactive task tree; `h` for keys
cylc workflow-state u-dr932            # one-shot list of task states
cylc log u-dr932                       # scheduler log
cylc cat-log u-dr932//<cycle>/<task>   # a task's job.out (add -f e for job.err)
squeue -u $USER                        # the Slurm side of the same thing
```

Task-level control matters here, because a suite is a graph and not a script — a
failure late on does not mean rebuilding:

```bash
cylc trigger u-dr932//20000101T0000Z/lfric_atm   # re-run one task, keep the build
cylc stop u-dr932                                # let running tasks finish
cylc stop --now --now u-dr932                    # stop the scheduler immediately
cylc clean u-dr932 -y                            # delete the run dir entirely
```

A successful run ends with `lfric_atm` `succeeded`; output is under
`$CYLC_RUN_BASE/<suite>/runN/share/output`, the extracted source under
`share/source`, and each task's logs under `log/job/<cycle>/<task>/NN/`.

Choose the variant with `LFRIC_STACK=cray|spack` — `cray` is the default and the only
one that scales across nodes (see Prerequisites).

**If `cylc install` dies in `cylc.post_install.log_vc_info`:** that plugin runs
`git diff` over the suite source, so a broken `GIT_EXTERNAL_DIFF` in your environment
takes the install down with it (`difft` on this machine crashes with
`<jemalloc>: Unsupported system page size`). Launch with `env -u GIT_EXTERNAL_DIFF`.

## Adapting this for your own suite

Drop your Rose/Cylc suite in a new directory here. Start from **what upstream already
does** and change only what the platform forces you to; u-dr932 is the worked example
and its [`README.md`](u-dr932/README.md) is the itemised diff.

1. **Sources.** Keep your `dependencies.yaml` and the upstream `merge_sources.py`
   extract; append `site/patch-sources.sh "$SOURCE_ROOT"` to its command so this
   repo's LFRic patches land on the cloned tree, and point `--mirror_loc` at
   `$REPO_ROOT/vendor/mirrors` if you want the offline path. Set
   `APPS_ROOT_DIR`/`CORE_ROOT_DIR`/`PHYSICS_ROOT` to the **extracted** tree under
   `$SOURCE_ROOT` — never to `vendor/` directly.
2. **Env.** Let `run-suite.sh` inject `ACTIVATE_ENV`/`LFRIC_STACK`/`LFRIC_PREFIX`/
   `LFRIC_ENV_VERSION`/`REPO_ROOT`; source `ACTIVATE_ENV` from both the root
   `init-script` (early enough for Cylc's own `cylc message`) and the platform
   `pre-script`. Take the compiler from the module with `FC = $FC` / `LDMPI = $LDMPI`
   / `FPP = $FPP` — do not hardcode one.
3. **Platform and placement.** Use `scripts/setup-cylc.sh`'s `isambard3` Slurm
   platform, set `RUN_METHOD = srun`, and give the model task `--nodes`,
   `--ntasks-per-node`, `--mem=0` and `--exclusive`. Do not set `--export=NONE`.
4. **Version.** Upgrade the app configs to the version this env builds with
   `rose app-upgrade`, then `rose macro --validate`.

The `site/` glue (`activate-env.sh`, `patch-sources.sh`, and `bin/launch-exe` for the
dedicated-XIOS-server case the Met Office launcher does not cover under `srun`) plus
`scripts/setup-cylc.sh` is reusable as-is — that is the contract between the built
environment and a science suite.
