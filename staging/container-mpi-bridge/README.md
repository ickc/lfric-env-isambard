# Container MPI: bridging the image's MPICH to Slingshot

**Question.** The container image (`container/`) carries the env's `spack` variant:
MPICH 5.0.1 (`ch4:ofi`) over a from-source libfabric with no Slingshot (`cxi`)
provider. On Isambard 3 that is TCP between nodes. Can a binary built against it
reach Slingshot by swapping host libraries in at run time, and which ones?

**Method.** [`probe.sbatch`](probe.sbatch), two nodes, one rank each, on bare metal:
`container/tests/pingpong.f90` (an `mpi_f08` ping-pong, as LFRic uses `mpi_f08`)
compiled with the host's `lfric-env/v2026.10.08/spack` module, then run with host
libraries substituted. Jobs 5866837–5866840, 2026-10-30.

## Results

| Run | Outcome | Latency | Bandwidth (8 MiB) |
|---|---|---|---|
| own MPICH + own libfabric, `srun --mpi=pmi2` | works (TCP) | 16.0 µs | 5.1 GB/s |
| own MPICH, `srun --mpi=pmix` | fails: `unsupported PMI version PMIx` | | |
| own MPICH + host libfabric 2.3.1 on `LD_LIBRARY_PATH` | fails: `getinfo ... No data available` | | |
| own MPICH + host libfabric 2.3.1 by `LD_PRELOAD` | fails: `version 'FABRIC_1.9' not found` | | |
| **host cray-mpich 9.1.0 via `lib-abi-mpich`**, default `srun` | **works (Slingshot)** | **2.4 µs** | 6.9 GB/s |

What the failures showed:

1. **PMI.** The env's MPICH (`pmi=default`, `~slurm`) speaks PMI-2 to `srun
   --mpi=pmi2`, not PMIx. Isambard 3's default plugin is `cray_shasta`.
2. **RPATH beats `LD_LIBRARY_PATH`.** `MPIR_CVAR_CH4_OFI_CAPABILITY_SETS_DEBUG=1`
   reported `current version: 20006`: MPICH still loaded *Spack's* libfabric 2.6,
   because `libmpi.so.12` carries a DT_RPATH to it. A library swap has to replace the
   file itself, not prepend a directory.
3. **Symbol versions.** Upstream libfabric 2.6 exports `FABRIC_1.9`, and MPICH built
   against it binds `fi_getinfo@FABRIC_1.9`. HPE's libfabric 2.3.1 stops at `FABRIC_1.8`
   (1.22.0 at `FABRIC_1.7`), so a 2.6-built MPICH cannot load it at all.
4. **The MPICH ABI holds, `mpi_f08` included.** cray-mpich 9.1.0 (`ANL base 4.3.0a1`)
   ran the MPICH 5.0.1-built `mpi_f08` binary unchanged: the allreduce check and the
   ping-pong both passed, at Slingshot latency.

Also found along the way: Isambard 3's libcxi and libfabric need **glibc ≥ 2.38**, so
a container must be on a distribution at least that new to load them at all
(Debian 12 has 2.36; Debian 13 has 2.41).

## What changed as a result

All in `container/`:

- The image is **Debian 13**, not 12 (glibc).
- The image's overlay pins **`libfabric@2.3.1`** (`container/spack/env/packages.yaml`),
  so its MPICH needs nothing newer than `FABRIC_1.8` and the host's library can load.
- The helper swaps libraries by **bind-mounting the host file over the container's**
  (through stable links the image provides, `container/gen-env.sh`), not via
  `LD_LIBRARY_PATH` — for both MPI modes:
  - `LFRIC_CONTAINER_MPI=host` (default): cray-mpich for libmpi/libmpifort, plus
    host libfabric, with the default `srun` plugin;
  - `LFRIC_CONTAINER_MPI=libfabric`: host libfabric only, `srun --mpi=pmi2`.
- `container/tests/mpi.sbatch` measures all three modes inside the container; its
  results are in `container/README.md`.
