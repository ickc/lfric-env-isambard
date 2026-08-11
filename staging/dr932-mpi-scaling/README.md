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

**The nodes really are shared, not merely shareable.** `SelectType = select/cons_tres`
with `CR_CORE_MEMORY`, so Slurm hands out cores rather than machines; `ExclusiveUser=NO`.
Over the 8 h 53 m window of job 5537502, **1493 distinct jobs from 20 different users**
touched the 32 nodes it was spread across (`results/node-sharing.txt`). Its unpinned
ranks (§4.3) were competing for cores and memory bandwidth with all of that. Hence
`--exclusive` in the fix, not just `--nodes`.

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
| 3b | uoe / `mpiexec -bind-to core -ppn 108` | 1 node × 108 | **108 / 108** | **8.95 µs** | 309 GB/s | **17.3 µs** |
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

**Row 3b at first looks like a mixed result, and chasing it produced the most useful
detail in this section.** Pinning Hydra (`-bind-to core -ppn 108`) does what it says —
108/108 ranks on their own core, where the unbound run had all of them sharing a 108-CPU
mask — and buys **1.5×** on both latency measures (13.2 → 8.95 µs allreduce,
25.7 → 17.3 µs ring). But it appeared to *lose* 23% of pairwise bandwidth: 402 → 309 GB/s.

Hydra fills cores linearly (the affinity dump confirms rank *i* → cpu *i*), so 108 ranks
on a 2 × 72 Grace node put **72 on socket 0 and 36 on socket 1**. `probe-1node-mapby.sbatch`
tests that against the mapping alternatives:

| mapping | rank→cpu | allreduce 8 B | pairwise 1 MiB | **ring 64 KiB** |
|---|---|---|---|---|
| `-bind-to core` (linear fill) | 0→0, 1→1, 2→2 | **8.90 µs** | 309.6 GB/s | **18.6 µs** |
| `-map-by numa` | 0→0, 1→72, 2→1 | 9.93 µs | **613.1 GB/s** | 28.7 µs |
| `-map-by socket` | 0→0, 1→72, 2→1 | 9.77 µs | 599.9 GB/s | 30.4 µs |
| `-map-by hwthread` | 0→0, 1→1, 2→2 | 10.97 µs | 308.6 GB/s | 18.1 µs |

The socket-imbalance mechanism is confirmed — `-map-by numa` alternates sockets exactly
as `srun` does and **doubles** the pairwise figure. But it is not a free win either: the
ring gets **54% worse** (18.6 → 28.7 µs), and the ring is the more honest proxy here.
The two mappings simply favour different neighbours. Linear fill puts ranks *i* and *i+1*
on the same socket, so nearest-neighbour exchange stays local; round-robin puts them on
opposite sockets and every neighbour hop crosses the chip-to-chip link. The pairwise test
pairs *i* with *i+54*, and 54 is even, so round-robin makes those same-socket — which is
what doubles it.

**LFRic's halo exchange is nearest-neighbour in the partition graph, so the ring is the
representative number and plain `-bind-to core` is the right choice.** The apparent
bandwidth regression is an artefact of this probe's *i*↔*i+54* pairing, not a defect in
the recommendation — `fix-u-dr932.patch` stands as written, and deliberately does not add
`-map-by`. Anyone tuning this for a different communication pattern should re-measure
rather than copy either row.

Worth noting where this lands against row 4: cray-mpich under `srun` beats *both* Hydra
mappings on *both* axes at once (5.2 µs, 1682 GB/s, 15.6 µs). There is no Hydra mapping
that trades its way to that — which is §5.2's argument in one line.

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

Two details worth having, since "it's ch3" invites the wrong follow-up questions:

- **Nothing at runtime can rescue it.** `--with-device=` is a `./configure` option
  (MPICH is Autotools, not CMake), so the device is a compile-time choice of which
  source subtree lands in `libmpi.so`. `MPIR_CVAR_NEMESIS_NETMOD` exists but the only
  netmod sources compiled into this library are `nemesis/netmod/tcp/*.c` and
  `netmod/none/none.c`.
- **It is not a one-flag fix either.** `ch4` alone buys nothing; it has to be
  `--with-device=ch4:ofi` *against a libfabric carrying the `cxi` provider* — Cray's,
  at `/opt/cray/libfabric/{1.22.0,2.3.1}`. This build links no libfabric at all, so it
  is a reconfigure and rebuild of MPICH and everything above it (HDF5, netCDF, XIOS,
  LFRic). At which point cray-mpich is already installed and already tuned.

**And the TCP is not merely bypassing RDMA — it is on a 1 GbE management link.**
`nemesis:tcp` picks its interface by resolving the local hostname. Measured on the
compute nodes themselves (`results/hsn-diag-*.out`):

| interface | speed | address | |
|---|---|---|---|
| `bond0` (one slave, `eno1`) | **1000 Mb/s** | 172.23.0.72/16 | in-band cluster/provisioning net — **what the hostname resolves to** |
| `hsn0` | **200000 Mb/s** | 10.243.0.66/16 | Slingshot NIC, IP-over-fabric |

So it is not the BMC/out-of-band network (that is invisible to the OS — no `/dev/ipmi0`),
but the node's own gigabit housekeeping NIC. Note Lustre does *not* go this way: it
reaches the fabric through kfabric at kernel level (`43@kfi,111@kfi:…/lfs1i3`).

**The link is saturated, not merely inefficient.** The probe's aggregate counts both
directions, so 0.23 GB/s over 2 nodes is 0.115 GB/s ≈ **0.92 Gb/s each way against a
1 Gb/s full-duplex link — 92% of line rate.** The clincher is that it does not depend on
rank count: 108 ranks give 0.23 GB/s and **4 ranks give 0.21 GB/s**. Per-message overhead
would scale with the number of ranks; a saturated wire does not. The model is pinned to a
link **200× narrower** than the one sitting idle beside it.

The obvious no-rebuild mitigation — `MPIR_CVAR_NEMESIS_TCP_NETWORK_IFACE=hsn0`, still
kernel TCP but over the right wire — **does not work**. `probe-2node-hsn.sbatch` runs the
identical 2×54 probe with the cvar unset and set: the unset arm reproduces (229.84 µs /
0.23 GB/s against 226.42 / 0.23 earlier), the set arm dies immediately with exit 15 and no
output. `probe-hsn-diag.sbatch` ruled out the easy explanations — `hsn0` is present,
addressed and up on both compute nodes, and it fails identically at 4 ranks, so it is not
a scale effect and not a missing interface. It also produces no diagnostic with stderr
merged.

Two hypotheses for the failure have since been tested and **both are dead**:

- *"`hsn0` is absent or down on compute nodes."* No — it is up, addressed and reports
  200000 Mb/s on both (`results/hsn-diag-*.out`).
- *"Node-to-node IP is not actually carried over `hsn0`"* — plausible, because
  Slingshot's native path is kernel kfabric and an IP interface existing does not imply
  IP is routed over it. **Disproved:** ping between two nodes' 10.243 addresses succeeds
  at 0.04–0.11 ms, *faster* than the same pair over `bond0` at 0.086–0.098 ms
  (`results/hsn-reach-*.out`). So the fast path is reachable and MPICH simply is not
  taking it. (The `nc` line in that job failed only because `nc` is not installed — a bug
  in the test, not a finding.)

TCP, not just ICMP, also works over `hsn0` — `probe-hsn-vars.sbatch` opens a real socket
between the two nodes' 10.243 addresses first, and it connects. So the fast path is
reachable at L3 *and* L4, and MPICH is simply not taking it.

That leaves how the knob is spelled. This `libmpi` carries several names for it, and its
*error* text names a different one than its cvar description does. Every spelling, tried
against a baseline on 4 ranks over 2 nodes:

| variable | rc | result |
|---|---|---|
| *(baseline, unset)* | 0 | 0.23 GB/s, ring 558.4 µs |
| `MPIR_CVAR_NEMESIS_TCP_NETWORK_IFACE=hsn0` | 1 | **no output at all** |
| `MPICH_NEMESIS_TCP_NETWORK_IFACE=hsn0` | 1 | **no output at all** |
| `MPIR_CVAR_NETWORK_IFACE=hsn0` | 1 | **no output at all** |
| `MPIR_CVAR_CH3_NETWORK_IFACE=hsn0` | 0 | 0.23 GB/s, ring 558.8 µs — **identical to baseline** |

The last row is the trap: it exits 0 and looks like it worked, but the numbers are
baseline to within noise, i.e. the variable is **silently ignored** — that is the name
MPICH's error strings mention, not a name it honours. Anyone who sets it will believe
they have moved onto the fast NIC and will not have. The three names it *does* recognise
all kill the job before it prints anything, with stderr merged.

**Unresolved, and closed here.** Three hypotheses eliminated (interface missing; IP not
carried; wrong spelling), no working variant found, and further reverse-engineering of a
misconfigured third-party MPICH is worth less than the recommendation it would compete
with — §5.2, an MPI that reaches Slingshot properly rather than over IP. Recorded so
nobody repeats it, and deliberately absent from `fix-u-dr932.patch`. The prize was real
(~200× of link speed on a stack nobody has to rebuild), which is why it was worth three
jobs to find out.

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

### 4.3b Is the 8 GB/core a real requirement? (no — measured)

The obvious objection to packing the ranks is memory. A Grace node is 225 GB for 144
cores — 1.6 GB/core — and `--mem-per-cpu=8G` × 108 reserves **864 GB**, nearly four whole
nodes. If the model genuinely needs that, packing it onto one node does not merely
perform differently, it OOMs, and the right fix would be to cap *ranks per node* at 28
rather than to take `--mem=0`.

It does not. `memory-footprint.sh` reads it out of Slurm accounting for the six completed
cycles (`results/memory-footprint.txt`):

| job | nodes | ranks/node | MaxRSS | → MB/rank | → 108 ranks on 1 node |
|---|---|---|---|---|---|
| 5537502 | 32 | 3.4 | 558 MB | 165 | 17.4 GB |
| 5524896 | 27 | 4.0 | 553 MB | 138 | 14.6 GB |
| 5516605 | 26 | 4.2 | 525 MB | 126 | 13.3 GB |
| 5532814 | 14 | 7.7 | 2179 MB | 282 | 29.8 GB |
| 5520538 | 10 | 10.8 | 3624 MB | 336 | 35.4 GB |
| 5541962 | 9 | 12.0 | 906 MB | 76 | 8.0 GB |

Two steps make that conversion sound rather than assumed:

- `JobAcctGatherType = jobacct_gather/cgroup`, and under Hydra the only processes Slurm
  itself launches are one `hydra_pmi_proxy` per node — the accounting reports
  `NTasks == NNodes` (32, 27, 26, 14, 10, 9), never 108. The ranks are descendants in the
  same per-node cgroup. So `MaxRSS` is the largest **per-node total**.
- That reading is falsifiable and survives: the rank count is 108 in *every* job, so a
  per-rank figure would be constant across the rows. It isn't — it tracks ranks-per-node,
  which is exactly what a per-node aggregate does.

**So the peak is 8–35 GB for the whole job against 225 GB on one node — 6× to 28× of
headroom, and the 864 GB request is over-provisioned by roughly 25–100×.** `--mem=0` is
safe here with room to spare.

Corroboration from the suite itself: the *dial3-gnu* branch pairs the same
`--mem-per-cpu=8G` with `--ntasks-per-node={{ CORES_PER_NODE }}` = 128, i.e. 1 TB per
node. That is boilerplate carried between platforms, not a figure anybody derived.

Two caveats, both real:

- `JobAcctGatherFrequency = 30` s, so a short allocation spike between samples is not
  captured. Sustained use across a 5–9 h job is.
- **This is C48_MG / L66, a small configuration.** The arithmetic is resolution-dependent
  and 8 GB/core could become a genuine requirement at C384 or C1152. Re-run
  `memory-footprint.sh` before assuming this headroom carries over; if it doesn't, keep
  the placement fix but derive `--ntasks-per-node` from the memory need instead of taking
  the whole node.

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

`fix-u-dr932.patch` applies to `dennissergeev/lfric_egp_bench@82f4a49`, and is proposed
upstream as **[dennissergeev/lfric_egp_bench#1](https://github.com/dennissergeev/lfric_egp_bench/pull/1)**
(draft, from `ickc/lfric_egp_bench:fix/isambard3-rank-placement`). It does two things
to `src/suites/u-dr932/flow.cylc`:

1. Give the `isambard3-gnu` `lfric_atm` directives the `--nodes` / `--ntasks-per-node`
   that the dial3 branch of the same file already has, and replace `--mem-per-cpu=8G`
   with `--mem=0` (the whole node's memory, which is what a packed node wants anyway).
   At 108 ranks that lands them all on one node and **no MPI traffic leaves it**, which
   is the only way this stack performs.
2. Set `SITE_MPI_LAUNCHER_OPTS` so `launch-exe` emits
   `mpiexec -bind-to core -ppn <ranks-per-node> -n <ranks>`, pinning the ranks.

This is a config-only change; it needs no rebuild. `cylc validate` passes on the patched
suite (this login node's FQDN contains `i3.isambard`, so a bare `cylc validate` here
exercises the `isambard3-gnu` branch — the one being changed).

**Its ceiling is one node — and the committed `rose-suite.conf` is already above it.**
The repo has `TOTAL_RANKS_REQ=216` (Denis' message quotes 108, presumably his working
copy). 216 renders as `--nodes=2 --ntasks-per-node=108`, so the patch collapses the
node count from up to 32 down to 2 but cannot take inter-node traffic to zero. With
`ch3:nemesis` there is no configuration that makes a genuinely multi-node run of this
stack fast, so **144 ranks is the hard limit**; above it the stack has to change.
(216 = 6 × 6² is otherwise a *better* rank count than 108 — it gives square
per-panel subdomains. See §4.4.)

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

**Since then, the two u-dr932s have been unified.** `examples/science-suites/u-dr932/`
was a copy of an older snapshot of this suite; it is now **Denis' suite itself**
(`lfric_egp_bench@e6ee57a`, a pinned submodule plus a patch) with his own working
configuration — deep hot Jupiter,
C48, l66, stretch 0.5 towards (−90, 0), dt = 50 s, 108 ranks — and a short list of
`[isambard3]` changes that includes §5.1's fix. That directory's `README.md` is the
itemised diff. Two things there supersede parts of this document:

- **§5.1's ceiling no longer applies.** The fix here was written for the UoE
  `ch3:nemesis` stack, where a genuinely multi-node run cannot be made fast, so 144
  ranks was the hard limit. On the environment this repo builds, the transport cause
  (§4.2) is gone, and the placement fix is about packing and repeatability rather
  than about avoiding the fabric.
- **The fork in `dependencies.yaml` is no longer needed.** Denis pins `lfric_apps` to
  `tommbendall/lfric_apps@4d8b921` (`TBendall/deep_hot_jupiter_forcing`) because at
  vn3.1 the deep hot Jupiter forcing lived only there. It is in MetOffice mainline as
  of `2026.07.1`.
- **`--export=NONE` has to go under `srun`**, which §5.1's patch keeps (correctly, for
  Hydra). `sbatch --export=NONE` sets `SLURM_EXPORT_ENV=NONE` in the job, and every
  `srun` inside inherits it — the model would start with none of the environment its
  module load set up.

## 7. Files

| file | what |
|---|---|
| `mpi-probe.c` | the probe: placement, binding, allreduce/pairwise/ring timings |
| `run-probe.sh` | builds + launches it against `uoe` / `cray` / `spack` × `mpiexec` / `mpiexec-bound` / `srun` |
| `probe-as-suite.sbatch` | Denis' `#SBATCH` block verbatim — the reproduction |
| `probe-1node.sbatch`, `probe-1node-bound.sbatch`, `probe-2node.sbatch` | the controls |
| `probe-1node-mapby.sbatch` | Hydra rank→core mapping: why `-bind-to core` is right for LFRic and `-map-by numa` is not |
| `probe-2node-hsn.sbatch`, `probe-hsn-diag.sbatch`, `probe-hsn-reach.sbatch`, `probe-hsn-vars.sbatch` | §4.2's closed thread: can the TCP fallback be moved off the 1 GbE management link onto `hsn0`? No — three hypotheses eliminated, no working variant |
| `model-run.sh`, `model-1node.sbatch`, `model-scatter.sbatch` | the same comparison on the real `lfric_atm` binary |
| `memory-footprint.sh` | §4.3b — whether packing the ranks starves them of memory, out of Slurm accounting |
| `denis-u-dr932/` | read-only snapshot of the scaling-relevant parts of his suite |
| `fix-u-dr932.patch` | the config-only fix, against his repo |
| `results/` | captured output backing every number above |
| `results/launch-exe-testmode.txt` | the launcher change checked against the real `launch-exe`, using its own `TEST_LAUNCH_EXE_EXEC` mode: `mpiexec -n 108 …` before, `mpiexec -bind-to core -ppn 108 -n 108 …` after |

Re-running everything needs Stage 1 built for the `cray` variant and one previous
`run-suite.sh u-dr932` (the model comparison reuses its binary and work directory).
