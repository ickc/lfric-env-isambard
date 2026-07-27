# u-dr932 is 3–4× slower on Isambard 3 than on Monsoon — reproduction and root cause

**Investigation staging area.** Not part of the reproducible core (Stage 1) and not a
science-suite example. It holds everything needed to reproduce, from scratch, the
scaling problem Denis Sergeev reported for
[`lfric_egp_bench/src/suites/u-dr932`](https://github.com/dennissergeev/lfric_egp_bench/tree/main/src/suites/u-dr932)
running on the **UoE conf-make stack**
(`/projects/u35v/sw/UoEGCC1120SWstackBuild/RoseStemSource.sh`) — an environment this
repo does *not* provide. Everything here is read-only with respect to Denis' work.

The conclusion in one line:

> **The suite never asks Slurm for a node count, so Slurm scatters its 108 ranks over
> as many as 32 nodes; the UoE stack's MPI is a from-source MPICH built
> `--with-device=ch3`, which has no libfabric and therefore no Slingshot — so every
> one of those inter-node messages goes over TCP, ~30× slower than the fabric.
> The ranks are also completely unpinned.**

None of the three is a property of Isambard 3. All three are fixed by suite config.

---

## 1. What was reported

> I've just checked, and the suite finally progressed to the next CRUN but it's still
> 3-4 times slower than on Monsoon (even taking into account GNU being slower than CCE).

with `TOTAL_RANKS_REQ=108`, `LFRIC_RES='C48_MG'`, `EXPT_DT=50`, `EXPT_RESUB='P10D'`
(→ 17 280 timesteps per cycle), `COMPILER='gnu'`.

## 2. Evidence A — Denis' own Slurm accounting

The suite's `[[lfric_atm]]` directives for `MACHINE == "isambard3-gnu"` are, verbatim
(`denis-u-dr932/flow.cylc.excerpt`):

```
--mem-per-cpu=8G
--ntasks=108
--cpus-per-task=1
--export=NONE
```

There is no `--nodes` and no `--ntasks-per-node`. Note that the *dial3* branch of the
very same file does have both — Isambard 3 is the one platform where they were dropped.

A Grace node here is 144 cores / 230 400 MB, i.e. **1600 MB per core**. Asking for
`--mem-per-cpu=8G` therefore caps a node at 28 of the job's ranks and lets Slurm place
the rest wherever it likes. `sacct` on Denis' actual `lfric_atm` jobs
(`dhj/c48_l66_s0p5_et`, all `--ntasks=108`):

| cycle | jobid | **nodes** | elapsed | state |
|---|---|---|---|---|
| 20000101 try08 | 5516605 | **26** | 05:07:20 | COMPLETED |
| 20000111 | 5520538 | **10** | 06:15:24 | COMPLETED |
| 20000121 | 5524896 | **27** | 08:59:01 | COMPLETED |
| 20000131 try02 | 5532814 | **14** | 06:27:42 | COMPLETED |
| 20000210 | 5537502 | **32** | 08:52:55 | COMPLETED |
| 20000220 try02 | 5541962 | **9** | 05:03:29 | COMPLETED |
| 20000101 try07 | 5514828 | 17 | 07:00:07 | TIMEOUT |
| 20000101 try05 | 5508504 | 9 | 05:00:18 | TIMEOUT |

108 ranks fit comfortably on **one** 144-core node. They were spread over **9 to 32**.
Identical work took **5 h to 9 h** depending on the draw — a 1.8× spread with no change
to the science, which is the signature of a placement problem, not a compute one. The
partial-node allocations also share their nodes with other users' jobs, so the unpinned
ranks compete for cores with whoever else landed there; that is where the run-to-run
variance comes from.

This is also why the problem is easy to miss: a request for 108 ranks with no node
count is *easier* for Slurm to place than a whole node, so the job starts sooner and
then runs slowly. Reproducing this, the 12-node scattered arm started within a minute
while the single-node arm queued behind `(Priority)` for the best part of an hour.

## 3. Evidence B — the reproduction

`mpi-probe.c` measures the three things that decide whether an LFRic run scales here:
node placement, per-rank CPU binding, and MPI transport (an 8-byte `MPI_Allreduce`,
the shape of the mixed solver's global sums; a 1 MiB pairwise exchange and a 64 KiB
nearest-neighbour ring, the shape of halo swaps). Same 108 ranks throughout.

```bash
sbatch staging/dr932-mpi-scaling/probe-as-suite.sbatch    # Denis' directives, verbatim
sbatch staging/dr932-mpi-scaling/probe-1node.sbatch       # 108 ranks, one node
sbatch staging/dr932-mpi-scaling/probe-1node-bound.sbatch # one node + Hydra pinning
sbatch staging/dr932-mpi-scaling/probe-2node.sbatch       # forced across the fabric
```

Captured output is in `results/`. Summary:

| # | stack / launcher | placement | ranks pinned | allreduce 8 B | pairwise 1 MiB | ring 64 KiB |
|---|---|---|---|---|---|---|
| 1 | **uoe / `mpiexec`** — *the suite as written* | **11 nodes** (1–13 ranks each) | **1 / 108** | **2494 µs** | **0.70 GB/s** | **1312 µs** |
| 2 | uoe / `mpiexec` | 2 nodes × 54 | 0 / 108 | 226 µs | 0.23 GB/s | 580 µs |
| 3 | uoe / `mpiexec` | 1 node × 108 | 0 / 108 | 13.2 µs | 402 GB/s | 25.7 µs |
| 4 | **cray / `srun`** — *this repo's env* | 1 node × 108 | **108 / 108** | **5.2 µs** | **1682 GB/s** | **15.6 µs** |
| 5 | cray / `srun` | 2 nodes × 54 | 108 / 108 | 6.7 µs | 7.12 GB/s | 24.4 µs |

Row 1 *is* the reported bug: submitting the probe with Denis' own `#SBATCH` block got an
11-node allocation with 1, 3, 5, 11, 12 and 13 ranks per node — exactly the shape `sacct`
shows for his model runs — and the collective latency is **190× worse** than the same
stack on one node (row 3).

Reading the rows against each other separates the causes:

- **placement** — rows 1 vs 3, same stack, same launcher: 2494 µs → 13.2 µs.
- **transport** — rows 2 vs 5, both 2 nodes × 54: 226 µs → 6.7 µs allreduce, 0.23 → 7.12 GB/s
  pairwise, 580 → 24 µs ring. That is the TCP-vs-Slingshot gap, **~30×**.
- **binding** — rows 3 vs 4, both a single node: even with no fabric involved,
  cray-mpich under `srun` (every rank on its own core) beats unpinned Hydra 2.5× on
  allreduce and 4× on bandwidth.

`probe-1node-bound.sbatch` (pinned Hydra, one node) is provided but was still queued
behind `(Priority)` when this was written — no row for it yet.

### 3b. The same comparison on the real model

`model-run.sh` re-runs the `lfric_atm` binary and work directory that
`run-suite.sh u-dr932` already built on this env, for 200 timesteps, changing nothing but
the allocation. Both arms request the same memory per core, so the *only* difference is
`--nodes=1 --ntasks-per-node=24` versus `--nodes=12 --ntasks-per-node=2`:

| arm | placement | 200 steps |
|---|---|---|
| `model-1node.sbatch` | 1 node × 24 ranks | **253 s** |
| `model-scatter.sbatch` | 12 nodes × 2 ranks | **288 s** |

**Read this carefully: it is 1.14×, not 3–4×, and that is the point.** This binary is
linked against cray-mpich, so even the scattered arm talks over Slingshot — the fabric
absorbs the scatter almost entirely. An earlier run of the *identical* scattered
configuration, differing only in how much memory it reserved (and therefore how many
other jobs shared its nodes), came in at 179 s, so 253 vs 288 is inside the run-to-run
noise of a shared machine anyway.

So scatter alone is not what costs Denis 3–4×; **scatter on an MPI that has to fall back
to TCP** is. The two causes multiply, which is also why fixing either one helps: pack the
job onto one node and the transport stops mattering; move to a Slingshot-capable MPI and
the placement stops mattering nearly as much. (The converse experiment — the scattered
arm on the UoE MPICH — is not runnable here: that binary would have to be rebuilt against
that stack. Probe rows 1 and 2 measure exactly that combination directly.)

## 4. Root causes

### 4.1 The suite lets Slurm choose the node count (primary)

`--mem-per-cpu=8G` with no `--nodes`/`--ntasks-per-node`. That memory request caps a node
at 28 of these ranks (230 400 MB / 8 GB), and with no node count asked for Slurm is free
to fill gaps on as many partly-occupied nodes as it likes — which on a busy machine it
does: the observed layouts were 1, 3, 5, 11, 12, 13 ranks per node across a dozen of them,
for a job that fits on one. Every rank pair that lands on different nodes turns a
shared-memory halo swap into a network round trip.

### 4.2 The UoE stack's MPI cannot use Slingshot (primary)

```
$ /projects/u35v/sw/KKsGCC1230LFRicSWstackConfMakeBuild/usr/bin/mpichversion
MPICH Version:      4.2.3
MPICH Device:       ch3:nemesis
MPICH configure:    --prefix=... --enable-fortran=all --enable-cxx --enable-threads=multiple
                    --enable-shared --enable-romio --with-device=ch3
```

`ch3` is MPICH's legacy device, superseded by `ch4`; `ch3:nemesis` does shared memory
within a node and **TCP sockets** between nodes. It is not linked against libfabric at
all (`ldd` on a binary built with it shows only `libmpi.so.12`), so the Slingshot `cxi`
provider — the whole point of a Cray EX — is unreachable. cray-mpich by contrast pulls in
`libfabric.so.1` and `libpmi*.so`.

It also explains `RUN_METHOD = mpiexec`: built without Slurm PMI, this MPICH cannot be
launched by `srun` and needs Hydra.

So §4.1 and §4.2 compound: the suite maximises the number of messages that must cross a
node boundary, and the stack makes each of those messages as slow as it can be.

### 4.3 Nothing pins the ranks (secondary)

For a `TARGET_PLATFORM` that is not `meto-ex1a`, the Met Office `launch-exe`
(`$APPS_ROOT_DIR/rose-stem/site/meto/common/bin/launch-exe`) reduces to

```sh
LAUNCHER_OPTS="-n ${TOTAL_RANKS}"
```

— no `-ppn`, no `-bind-to`. Denis' job.out confirms the emitted command is
`mpiexec -n 108 .../lfric_atm configuration.nml`. Hydra does not bind by default, so all
108 ranks share one 108-CPU affinity mask (probe row 3: `cpus=0-125 (width=108)`) and the
kernel migrates them across the two NUMA sockets of the Grace superchip at will. `srun`
pins one rank per core without being asked (row 4: `cpus=0-0 (width=1)`).

`NUMA_REGIONS_PER_NODE = 0` in the `ISAMBARD3GNU` environment block is a related
mis-setting — a Grace node has 2 — though on this code path `launch-exe` never reads it.

### 4.4 Not causes

- **GNU vs CCE, and GCC 12.3 vs 14.3.** Not measured here, and not the thing being
  claimed: the probe numbers above are compiler-independent, and they already account
  for a 30× transport gap. Worth recording what the compilers actually are, though,
  since it is easy to assume more difference than there is — the UoE stack is
  gfortran 12.3.0, this repo's `cray` variant is gfortran 14.3.0 behind `ftn`, and
  **neither passes an `-mcpu`**, so both generate generic AArch64 rather than
  Neoverse-V2 code. (GCC 12.3 does accept `-mcpu=neoverse-v2`; nobody is asking for it.)
- **108 being an awkward rank count.** 108 = 6 panels × 18, and 18 is not a square, so each
  rank owns a 16×8 patch rather than a square one. Real but small (halo:volume 0.375 vs
  0.333 for 96 ranks). Worth noting that **96** (6 × 4²) and **54** (6 × 3²) both give square
  subdomains *and* fit one node.
- **Filesystem.** Real, but a separate bug: two of Denis' cycles died with
  `nc_open ... NetCDF: HDF error` reading their restart, which is HDF5's `flock()` on a
  filesystem that does not support it. This repo's `site/activate-env.sh` already exports
  `HDF5_USE_FILE_LOCKING=FALSE` for exactly this.

## 5. The fix

### 5.1 For Denis' suite as it stands (keeping the UoE stack)

`fix-u-dr932.patch` applies to `dennissergeev/lfric_egp_bench@82f4a49`. It does two things
to `src/suites/u-dr932/flow.cylc`:

1. Give the `isambard3-gnu` `lfric_atm` directives the `--nodes` / `--ntasks-per-node`
   that the dial3 branch of the same file already has, and replace `--mem-per-cpu=8G`
   with `--mem=0` (the whole node's memory, which is what a packed node wants anyway).
   108 ranks then land on one node and **no MPI traffic leaves it**, which is the only way
   this stack performs.
2. Set `SITE_MPI_LAUNCHER_OPTS` so `launch-exe` emits
   `mpiexec -bind-to core -ppn <ranks-per-node> -n <ranks>`, pinning the ranks.

This is a config-only change; it needs no rebuild.

Its limit is the node: with `ch3:nemesis` there is no configuration that makes a
**multi-node** run of this stack fast, so 144 ranks is the ceiling. For anything larger the
stack has to change.

### 5.2 The durable fix — build against a Slingshot-capable MPI

Use this repo's `cray` environment (cray-mpich + `libfabric` `cxi` + `srun`), which is what
`examples/science-suites/` already does; see §6 and that directory's README. Probe rows 4
and 5 are that environment: it keeps ~7 µs collectives *across* nodes, where the UoE stack
needs 226 µs.

## 6. What this changes in `examples/science-suites/`

The suites here were already on the right side of all three causes — `RUN_METHOD = srun`,
explicit `--nodes` + `--mem=0`, and `site/bin/launch-exe` launching with `srun` — which is
why u-dr932 and u-dn704 run and scale here. Two things came out of this investigation:

- `LPPN` was `128` in all three suites' `flow.cylc`, a Monsoon number. A Grace node is
  **144**, so `LFRIC_NODES = ceil(TOTAL_RANKS_REQ / LPPN)` over-counted nodes for any rank
  count in (128, 144] — e.g. 144 ranks asked for 2 nodes and got split across the fabric
  for no reason. Fixed.
- The placement contract was implicit. It is now written down in
  `examples/science-suites/README.md` ("Placement and MPI transport"), with these numbers,
  so the next suite ported here does not rediscover it.

## 7. Files

| file | what |
|---|---|
| `mpi-probe.c` | the probe: placement, binding, allreduce/pairwise/ring timings |
| `run-probe.sh` | builds + launches it against `uoe` / `cray` / `spack` × `mpiexec` / `mpiexec-bound` / `srun` |
| `probe-as-suite.sbatch` | Denis' `#SBATCH` block verbatim — the reproduction |
| `probe-1node.sbatch`, `probe-1node-bound.sbatch`, `probe-2node.sbatch` | the controls |
| `model-run.sh`, `model-1node.sbatch`, `model-scatter.sbatch` | the same comparison on the real `lfric_atm` binary |
| `denis-u-dr932/` | read-only snapshot of the scaling-relevant parts of his suite |
| `fix-u-dr932.patch` | the config-only fix, against his repo |
| `results/` | captured output backing every number above |
| `results/launch-exe-testmode.txt` | the launcher change checked against the real `launch-exe`, using its own `TEST_LAUNCH_EXE_EXEC` mode: `mpiexec -n 108 …` before, `mpiexec -bind-to core -ppn 108 -n 108 …` after |

Re-running everything needs Stage 1 built for the `cray` variant and one previous
`run-suite.sh u-dr932` (the model comparison reuses its binary and work directory).
