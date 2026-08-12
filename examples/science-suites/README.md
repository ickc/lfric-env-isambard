# The science-suite examples — run real LFRic suites (Rose/Cylc)

This directory holds the **science-suite examples**: running real LFRic
**Rose/Cylc science suites** on the environment that Stage 1 built. Scientists run
LFRic this way — `cylc` schedules the suite's task graph (extract → build → mesh →
run) and submits each task to Slurm; `rose` materialises each task's namelist
config. So these examples run the suites *that* way, rather than reinventing it.

> The reproducible **core** of this repo is the environment (Stage 1,
> `scripts/build.sh`). These suites are **not** that core — they are things you do
> *with* it. Treat them as templates to copy and adapt. u-dr932 is
> [Denis Sergeev's own suite](https://github.com/dennissergeev/lfric_egp_bench) on
> GitHub; u-dn704 and u-dt000 are Met Office suites in MOSRS subversion
> (`roses-u/d/n/7/0/4/trunk` and `d/t/0/0/0/trunk`). **None is copied into this repo** —
> each is fetched from its own upstream and adapted by a patch.

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
| **u-dr932** | GungHo Shallow/Deep Hot Jupiter temperature forcing (C48 multigrid, idealised) | ✅ **builds + runs end-to-end** — and is now **Denis Sergeev's suite itself** ([`lfric_egp_bench@e6ee57a`](https://github.com/dennissergeev/lfric_egp_bench/tree/main/src/suites/u-dr932)), with his working configuration, rather than a copy of an older snapshot of it; see [`u-dr932/README.md`](u-dr932/README.md) for the itemised `[isambard3]` diff. Validated on the **cray** environment: one Grace node, 108 ranks `--exclusive`, the full 17 280-timestep cycle (deep hot Jupiter, C48, l66, mesh stretched 0.5 towards −90/0, dt = 50 s) in **1 h 37 m** against 5 h 07 m – 8 h 59 m for the same cycle on the UoE stack, with all three XIOS diagnostic files written. Self-contained (radiation off, analytic init; no external data). Needs `patches/31-lfric_apps-slow-physics-mphys-field-patch.sh`: vn3.2 stopped creating the UM-physics fields for a forcing-only config while `slow_physics` still fetched `dtheta_mphys`. |
| **u-dn704** | LFRic Atm NWP GAL9 @ C12 | ✅ **builds + runs end-to-end, multi-node** on the **cray** environment — 24 model ranks + 1 dedicated XIOS server across 2 nodes over **Slingshot (cxi)**; the XIOS server wrote the native-UGRID parallel-HDF5 output (`lfric_gal_diagnostics.nc` ~62 MB); re-validated on the `2026.07.1` / vn3.2 stack. Now built on the upstream Met Office suite itself (`roses-u/d/n/7/0/4/trunk` @ r361458) + `patches/suites/42-*`, which needs **no** version-alignment step: upstream took this suite to vn3.2 / `2026.07.1` in July 2026, the same release this environment builds. The NWP ancils, start dump and `um_aux` ctldata are **staged on Isambard 3** at the default `BIG_DATA_DIR=/projects/u35v/sw/lfricdata` and read offline at run time (GA9 spectra come from the vendored socrates — no MO `um_aux` clone, no SSO). |
| **u-dt000** | LFRic Atm Uranus/Neptune (ice giant) temperature forcing | ✅ **builds + runs end-to-end** — the long-standing `held_suarez_sigma_b` blocker is **resolved**. Its science, `theta_forcing='ice_giants_obs_like'`, comes from [`dennissergeev/lfric_apps@ice_giants_tf`](https://github.com/dennissergeev/lfric_apps/tree/ice_giants_tf) forward-ported vn3.0 → vn3.2 (`patches/optional/32-*`); the suite itself is the upstream Met Office one, checked out from MOSRS (`roses-u/d/t/0/0/0/trunk` @ r348703) + `patches/suites/41-*`, on the Met Office `merge_sources.py` extract, with its namelists re-derived by `rose app-upgrade vn3.0 → vn3.2`. Validated on the **cray** environment: one Grace node, 108 ranks `--exclusive`, the full 28 800-timestep cycle (**upstream's current science** — C96_MG, 50 levels, dt = 300 s, `PHYSICS_CONF='stability'`, analytic start) in **5 h 00 m**, `slow_physics: Running Ice Giants obs-like theta forcing` at every step, dry mass conserved to 6.2 × 10⁻⁷, 0.58 GB of XIOS output. Its three energy-conservation diagnostics read `Infinity` from step 1 — [u-dr932's known 32-bit overflow](u-dr932/known-issues/energy-diagnostics-overflow-at-32-bit.md), not a regression: upstream runs this suite at `RDEF_PRECISION=32`, the physical fields are finite and mass is conserved. Not comparable with the 3 h 56 m recorded before this baseline change, which was C48_MG at dt = 120 s. Self-contained (no ancils, no start dump). **The science is not validated** — only that the suite runs its intended forcing here; see [`u-dt000/README.md`](u-dt000/README.md). |

### Version alignment (forward-porting suite configs)

A suite's namelists must match the LFRic the environment builds (`2026.07.1` = apps
vn3.2), not the version the suite was written for. How big that gap is depends on the
suite, and it is not constant: **u-dn704 has no gap at all** now that it is taken from
its real upstream, because the Met Office moved it to vn3.2 themselves; u-dr932 (vn3.1)
and u-dt000 (vn3.0) still need the upgrade, which their stagers run. These are mechanical, non-science edits — e.g. u-dr932/u-dn704's
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
a fork onto a tag).

**u-dt000 was the hard case, and it is worth reading as the worked example.** Its
`theta_forcing='ice_giants_obs_like'` is in no MetOffice tag at all: it lives on
[`dennissergeev/lfric_apps@ice_giants_tf`](https://github.com/dennissergeev/lfric_apps/tree/ice_giants_tf),
which also promotes three Held-Suarez constants to namelist items — the reason the run
died on `Cannot match namelist object name held_suarez_sigma_b` for so long. The
two-source `dependencies.yaml` form is exactly the right expression of that and does not
work *yet*, because the branch is still based on vn3.0 and merging it onto `2026.07.1`
conflicts in the gungho rose-meta. So the merge is done once, here, and carried as an
**opt-in** source patch (`patches/optional/32-lfric_apps-ice-giants-forcing-*`) that the
suite's own extract task applies — opt-in because its new metadata items are
`compulsory=true` and would break every other suite's namelists. Full story in
[`u-dt000/README.md`](u-dt000/README.md).

## How it works here (what was adapted)

**No suite is copied into this repo.** Each one is fetched from its own upstream and
staged by a patch script — the same treatment Stage 1 gives its LFRic sources — so the
difference between what a scientist runs and what runs here is a **real diff**.

Upstream comes in two kinds, because the suites have two kinds of home:

| suite | upstream | staged by | site diff |
|---|---|---|---|
| u-dr932 | submodule `vendor/lfric_egp_bench` @ `e6ee57a` | `patches/40-lfric_egp_bench-u-dr932-patch.sh` | 419 lines, 5 files |
| u-dt000 | MOSRS `roses-u/d/t/0/0/0/trunk` @ r348703 | `patches/suites/41-roses-u-u-dt000-patch.sh` | 434 lines, 5 files |
| u-dn704 | MOSRS `roses-u/d/n/7/0/4/trunk` @ r361458 | `patches/suites/42-roses-u-u-dn704-patch.sh` | 455 lines, 7 files |

u-dr932 is Denis Sergeev's, on GitHub, so it is a pinned submodule. **u-dn704 and
u-dt000 are Met Office rose suites and live in MOSRS subversion** — and are staying
there: [simulation-systems#566](https://github.com/MetOffice/simulation-systems/discussions/566)
moved the *source* extraction to git, explicitly *"not where the workflows themselves
reside"*. There is nothing to vendor, so they are **checked out the way a Met Office
scientist checks them out** (see below) and the site patch is applied to that checkout.

Anything upstream absorbs drops out of the patch, and this is not theoretical: u-dr932's
shrank by 40 lines the day Denis merged our placement fix, and when u-dn704 moved onto
its real upstream it lost its whole `rose app-upgrade` step, because the Met Office had
already taken that suite to vn3.2 and `2026.07.1` — the release this environment builds.
Reversing the patch gives the upstream suite back (`git apply -R` / `pixi run unpatch`
for the submodule, `svn revert -R` for the checkouts), and the patch file is directly the
change to propose upstream.

### Getting a suite from MOSRS

`rosie` ships in the environment Stage 1 builds, and
[`site/rose.conf`](site/rose.conf) gives it the `u-` prefix map that a Met Office site
install would normally supply. You need a **MOSRS account** — `roses-u` is not
anonymously readable.

```bash
. examples/science-suites/site/activate-env.sh
rosie checkout u-dn704                       # -> ~/roses/u-dn704
svn update -r 361458 ~/roses/u-dn704         # the revision the patch is cut against
```

That `svn update` is not optional: the stagers read `svn info` and **refuse** a checkout
at any other revision, because a site patch that happens to apply to a neighbouring
revision would hand you a suite nobody validated. To base on a different revision
deliberately, re-cut the patch and say so with `LFRIC_SUITE_REV=<rev>`.

`rosie checkout` shells out to `svn checkout`; stock `/usr/bin/svn` on the login nodes is
enough (the Met Office's patched svn matters for FCM keywords and commits, not for
reading). If svn asks for your password on every command, there is no usable password
store configured — point it at gpg-agent (`password-stores = gpg-agent` in
`~/.subversion/config`, a `pinentry-program` in `~/.gnupg/gpg-agent.conf`, and
`export GPG_TTY=$(tty)` in your shell rc). That caches for the agent's TTL, per login
node.

`run-suite.sh` looks in `~/roses/<suite>` by default; set `LFRIC_SUITE_DIR` to use a
checkout elsewhere. It prints the exact command above if the checkout is missing.

Beyond that, each suite is the upstream Rose/Cylc suite with three site-specific
changes, so it runs against *our* env on Isambard 3:

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

   u-dt000 appends one more step, by path: `patches/optional/32-lfric_apps-ice-giants-
   forcing-patch.sh`, which is its *science* — Denis Sergeev's `ice_giants_tf` branch
   forward-ported to vn3.2. It is deliberately outside the shared stack, because the
   metadata it adds is `compulsory=true` and would make every other suite's namelists
   invalid. See [`patches/optional/README.md`](../../patches/optional/README.md).

   All three suites are on this extract now. The bespoke offline extract this repo
   used to carry for u-dn704 (`site/extract-sources.sh`, a `git archive` out of the
   vendored submodules) is gone: `USE_MIRRORS=true` with `MIRROR_LOC` pointed at
   `vendor/mirrors/` is the same property using upstream's own mechanism.
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
- **For u-dr932, its suite submodule too:**
  `git submodule update --init vendor/lfric_egp_bench`. `run-suite.sh` stages and
  patches it for you; it fails with that command in the message if it is missing.

## Run it

Everything below happens on a **login node**. The Cylc scheduler is a long-lived
process that lives there and submits each task to Slurm itself, so **nothing here is
wrapped in `sbatch`** — `sbatch`-ing the scheduler is the classic mistake.

```bash
bash examples/science-suites/run-suite.sh u-dr932   # cray environment (the default)
```

That is the whole launch. `run-suite.sh` is a convenience wrapper, not a new
mechanism — it does four things you could do by hand:

```bash
# 1. put the built environment on PATH (rose/cylc/psyclone come from its view)
. examples/science-suites/site/activate-env.sh

# 2. stage the suite: rose app-upgrade to the version this env builds, then the
#    Isambard 3 site patch. All three suites live in a submodule, so all three
#    need this (patches/41-* for u-dt000, patches/42-* for u-dn704).
bash patches/40-lfric_egp_bench-u-dr932-patch.sh

# 3. write the `isambard3` Slurm platform + a roomy cylc-run dir into ~/.cylc/flow
bash scripts/setup-cylc.sh

# 4. validate, install and play, telling the suite which environment to load.
#    NOTE the path: u-dr932 is the STAGED SUBMODULE, not a directory under
#    examples/science-suites/ (which holds only its README and known-issues).
cylc vip vendor/lfric_egp_bench/src/suites/u-dr932 --workflow-name u-dr932 \
  -S "REPO_ROOT='$PWD'" \
  -S "LFRIC_STACK='cray'" \
  -S "LFRIC_PREFIX='<the PREFIX Stage 1 installed into, unversioned>'" \
  -S "LFRIC_ENV_VERSION='<the version from ./VERSION>'" \
  -S "ACTIVATE_ENV='$PWD/examples/science-suites/site/activate-env.sh'"
```

Anything you pass to `run-suite.sh` after the suite name goes straight to `cylc vip`,
so suite settings are overridden the usual way — `-S "EXPT_RUNLEN='P1200D'"`,
`-S TOTAL_RANKS_REQ=54`, `--pause`, and so on. String values must be quoted for `-S`
(`-S EXPT_RUNLEN=P1200D` is rejected as `Invalid template variable`); numbers and
booleans need no quotes.

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

**If `cylc install` says `previous installations were from <some other path>`:** a
workflow name is bound to the directory it was first installed from, recorded in
`~/cylc-run/<suite>/_cylc-install/source`. Moving a suite from a copy under
`examples/science-suites/` into a `vendor/` submodule changes that path — both u-dt000
and u-dn704 hit this. Either `cylc clean <suite> -y` (which deletes the old runs) or,
to keep them, repoint that one symlink at the suite's new home.

## Adapting this for your own suite

Prefer **pinning the upstream suite as a submodule under `vendor/` and carrying a
patch**, as u-dr932 does, over copying it in — a copy drifts silently, which is exactly
how the two u-dr932s came to differ. Wire it up in `run-suite.sh`'s `case` block and add
a `patches/NN-<repo>-<suite>-patch.sh`.

**"It's a MOSRS suite, so it can't be a submodule" is worth testing before you accept
it.** u-dn704 and u-dt000 both live in `roses-u` subversion, which is SSO-gated and not
git — but a repository that already contains a checkout of them does exist and *can* be
pinned, and its `.svn/wc.db` even records which revision it was taken at (see
[`u-dn704/README.md`](u-dn704/README.md)). Pinning that and diffing against it beats
copying, because the copy is the thing that drifts. Only fall back to a copy when there
is genuinely no git object anywhere that contains the suite.

Then start from **what upstream already does** and change only what the platform forces
you to; u-dr932 is the worked example and its [`README.md`](u-dr932/README.md) is the
itemised diff.

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
   `--ntasks-per-node`, `--mem=0` and `--exclusive`. If you keep `--export=NONE` (and
   you should — it is what makes the job stateless), `export SLURM_EXPORT_ENV=ALL` in
   the platform `pre-script`, or every `srun` step starts with no environment at all.
4. **Version.** Upgrade the app configs to the version this env builds with
   `rose app-upgrade`, then `rose macro --validate`.

The `site/` glue (`activate-env.sh`, `patch-sources.sh`, and `bin/launch-exe` for the
dedicated-XIOS-server case the Met Office launcher does not cover under `srun`) plus
`scripts/setup-cylc.sh` is reusable as-is — that is the contract between the built
environment and a science suite.
