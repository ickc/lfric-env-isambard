# The LFRic environment as a container

A container image of the LFRic Apps environment that Stage 1 builds: the
`spack` variant (MPICH, HDF5, netCDF, XIOS, PSyclone, Rose, Cylc, ... all from
Spack) on **gcc 14.3**, for **generic aarch64**, on **Debian 13**. Pull it and
run it anywhere with an Arm64 Linux and a container engine. On Isambard 3 it
also runs **multi-node MPI over Slingshot** and **Cylc suites through Slurm**,
through a small host helper, [`bin/lfric-container`](bin/lfric-container).

- Image: `ghcr.io/ickc/lfric-env:<version>` (OCI), and the same as a SIF:
  `oras://ghcr.io/ickc/lfric-env:<version>-sif`. `<version>` is
  [`../stage1/VERSION`](../stage1/VERSION).
- Inside: everything `module load lfric-env/<version>/spack` gives you on the
  host, already loaded: `FC=mpif90`, `CXX=mpic++`, `LDMPI`, `FFLAGS`/`LDFLAGS`,
  `rose`, `cylc`, `psyclone`, `xios_server.exe`, the Python analysis stack.

## Quick start on Isambard 3

```bash
# 1. The image, as a SIF (once; 3.0 GB). Either form gives the same filesystem.
apptainer pull lfric-env.sif oras://ghcr.io/ickc/lfric-env:v2026.10.08-sif
#   or: apptainer pull lfric-env.sif docker://ghcr.io/ickc/lfric-env:v2026.10.08

# 2. The helper: in a checkout of this repo, container/bin/lfric-container.
export LFRIC_CONTAINER_IMAGE=$PWD/lfric-env.sif
alias lfric-container=/path/to/lfric-env-isambard/container/bin/lfric-container

# 3. Use it.
lfric-container shell                          # interactive, environment loaded
lfric-container exec $FC ...                   # one command
lfric-container exec srun -n 288 ./lfric_atm configuration.nml   # in a job: MPI over Slingshot
lfric-container cylc vip ~/roses/u-dn704       # a Cylc suite, jobs through Slurm
```

Only `apptainer` is needed on the host. Plain `apptainer exec lfric-env.sif ...`
works too, for anything that does not need Slurm, MPI across nodes, or a
long-running Cylc scheduler; the helper adds exactly those (below).

## Anywhere else

The image is an ordinary OCI image, so on a laptop or workstation (Arm64, or
x86 under emulation):

```bash
docker run --rm -it ghcr.io/ickc/lfric-env:<version>          # or podman
apptainer exec docker://ghcr.io/ickc/lfric-env:<version> bash
```

MPI then is the container's own MPICH: `mpiexec -n 4 ./prog` inside the
container (Hydra; TCP or shared memory). The Slurm and Slingshot parts below are
Isambard 3 glue and are simply absent elsewhere.

## How it works

### One image, built by Stage 1

[`Containerfile`](Containerfile) runs Stage 1 *itself* — the same `stage1/`
tree, `pixi run build-spack`, its variant assertions and its smoke test — in a
Debian 13 build stage, then copies the install tree into a fresh Debian 13. The
environment templates in `stage1/spack-env/` are used unmodified; the image's
only changes are an overlay in [`spack/env/`](spack/env/) (Spack's user scope):

| Overlay | Why |
|---|---|
| `target=aarch64`, generic granularity | runs on any Arm64, not just Grace (neoverse_v2) |
| `libfabric@2.3.1` | the host's libfabric ABI, so it can be swapped in (MPI, below) |
| binary cache on the build mount | a failed build resumes; not in the image |

gcc 14.3 is built by Spack in its own stage (Debian's gcc 14.2 bootstraps it)
and installed as `/usr/bin/{gcc,g++,gfortran}-14` — the SLES layout
`stage1/spack-env/common.yaml` already declares, so no template changes.

**Why Debian 13**, not EESSI's other choice, Debian 12: on a Cray EX the
container must load the host's Slingshot libraries (`libcxi`, `libfabric`), and
those are built against the host's glibc — 2.38 on Isambard 3's SLES 15 SP7.
Debian 12 has glibc 2.36 and cannot load them; Debian 13 has 2.41. EESSI builds
on `debian13` too (`ghcr.io/eessi/build-node:debian13`).

### Formats and engines

The **OCI image is the portable artifact**: Docker, Podman, Apptainer,
Kubernetes and every registry speak it. A SIF is derived from it (`apptainer
build x.sif oci-archive://...`, or `apptainer pull docker://...`), and both are
published. On Isambard 3 the image is **built with podman-hpc** (a Containerfile
build needs no root with Podman) and **run with Apptainer** (no daemon, one
read-only file on Lustre that every node shares, `srun`-friendly).

### Activation

The environment is on in every way into the container: login shells
(`/etc/profile.d`), `apptainer exec|run|shell` (`/.singularity.d/env`), and
`podman|docker run` (the entrypoint). All three source
[`activate.sh`](rootfs/opt/lfric-env/container/activate.sh), which drops the
host's Lmod/Cray state (Apptainer passes the host environment through) and
applies the module's environment, frozen at build time by
[`gen-env.sh`](gen-env.sh) from a real `module load` in a clean shell. Lmod is
in the image too, and `module list` shows `lfric-env`.

### Slurm inside the container

A Cylc scheduler submits jobs with `sbatch` and polls with `squeue` — from
inside the container. The image cannot carry a Slurm client (it must match the
site), and the host's binaries need the host's glibc. So the helper binds the
host's Slurm binaries, its **dynamic loader** and library directories under
`/host/slurm`, plus the munge socket and the configless config cache, and the
image's `sbatch`, `squeue`, ... ([`host-slurm`](rootfs/opt/lfric-env/container/bin/host-slurm))
run each one through the host's loader with the host's libraries.

### MPI

A rank `srun` starts runs on the host, so the image's `srun`
([wrapper](rootfs/opt/lfric-env/container/bin/srun)) keeps your command line
and inserts the helper in front of the program: each rank enters its own
container with your environment (`--multi-prog` files are rewritten the same
way). How a rank reaches the interconnect is `LFRIC_CONTAINER_MPI`:

| Mode | What the rank runs on | 2 nodes, 1 rank each | 1 node, 2 ranks |
|---|---|---|---|
| `host` (default) | the host's **cray-mpich**, swapped in for the container's MPICH (MPICH ABI: `libmpi.so.12`, `libmpifort.so.12`) | **2.5 µs**, 3.7 GB/s | 0.34 µs, 16 GB/s |
| `libfabric` | the container's MPICH, with the host's Slingshot **libfabric** (`cxi`) swapped in | **2.9 µs**, 3.7 GB/s | 1.4 µs, 7.6 GB/s |
| `none` | the container's MPICH as built (libfabric `tcp`) | 20 µs, 2.8 GB/s | 1.4 µs, 6.9 GB/s |

`tests/pingpong.f90`, job 5869785, 2026-10-31. Bare metal, for comparison: cray-mpich
2.4 µs, the env's own MPICH over TCP 16 µs
([`staging/container-mpi-bridge/`](../staging/container-mpi-bridge/)).

Every rank is its own container, so two ranks on a node are in two user namespaces,
where the kernel refuses the cross-memory attach (CMA) both MPICHs use for large
on-node messages. The helper therefore sets `MPICH_SMP_SINGLE_COPY_MODE=NONE` and
`MPIR_CVAR_CH4_CMA_ENABLE=0` for each rank (unless you set them): on-node messages go
through shared memory instead, at the cost shown in the last column.

The swap binds the host file *over* the container's library (a stable path
in the image, [`gen-env.sh`](gen-env.sh)), because the environment's own
libraries find libmpi through RPATH, which `LD_LIBRARY_PATH` cannot override.
The test program uses `mpi_f08`, as LFRic does — the bindings the MPICH ABI
promise covers least — and passes in every mode.

### Cylc

Two things differ from a bare-metal run, and the helper handles both:

- **The scheduler must outlive the command.** A process left running by
  `apptainer exec` loses the image's filesystem when the command returns. So
  `lfric-container cylc ...` (and `exec --instance`) run in a persistent,
  per-user Apptainer **instance** on the login node; schedulers live in it.
  `lfric-container instance stop` ends it (and any schedulers in it).
- **Jobs start outside the container.** Slurm starts a job on the compute node
  in the host's environment. The container's Cylc site config
  ([`global.cylc`](rootfs/opt/lfric-env/container/etc/cylc/flow/global.cylc))
  is the module's plus a `global init-script` on the `isambard3` platform that
  re-runs the job file inside the container (`$0`, Slurm's copy). Suites need no change.

Verified with u-dn704 (GAL9 NWP, `examples/science-suites/`), unchanged, started with
`lfric-container exec --instance bash examples/science-suites/run-suite.sh u-dn704`:
extract, both builds, the mesh and the model all green — `lfric_atm` as 24 model ranks
plus a dedicated XIOS server through `srun --multi-prog`, split 13/12 over two nodes, on
cray-mpich over Slingshot (`cxi0`), writing the same 62 MB `lfric_gal_diagnostics.nc`
as on bare metal (2026-10-31).

Everything else is business as usual: the suite's own `flow.cylc`,
`dependencies.yaml`, `launch-exe` and `srun` lines run as they do on the host.

## Building

```bash
bash container/fetch.sh                             # login node: every Spack source
sbatch container/build.sbatch                       # image + SIF
sbatch --export=ALL,PUSH=1 container/build.sbatch   # ... and push to GHCR
```

`fetch.sh` is the container's counterpart of Stage 1's `pixi run fetch`: it downloads
every source the build compiles (Stage 1's spack variant with the overlay, plus gcc) on
the login node, so a source host that is down or refuses robots fails there in a
minute, not hours into a compute job; the build then needs the network only for the
Debian base image, apt, pixi and Spack's bootstrap. The build runs on a Grace compute
node (it is Stage 1's full build, plus gcc; ~5 h from cold on 72 cores, minutes with a
warm cache). Settings are environment variables, listed at the top of
[`build.sh`](build.sh). The Spack caches persist in `$LFRIC_CONTAINER_BASE/cache`, so a
rebuild reinstalls from binaries; a failed package's full log is kept in
`cache/failed-logs/`. Pushing uses `gh auth token` (with the `write:packages` scope),
handed to each push and never stored.

Two traps the build avoids, worth knowing if you change it: rootless podman's
fuse-overlayfs root broke heavily parallel builds silently, so every build step
compiles in a node-local directory mounted as `/tmp`; and binutils needs gcc's LTO
plugin in `/usr/lib/bfd-plugins`, or `ar` indexes no symbols of an LTO object (both
cost matplotlib its bundled agg before they were fixed).

## Testing

```bash
export LFRIC_CONTAINER_IMAGE=/path/to/lfric-env_<version>.sif
sbatch --export=ALL container/tests/mpi.sbatch              # -> CONTAINER_MPI_OK
sbatch --export=ALL container/tests/minimal-compile.sbatch  # -> LFRIC_ATM_OK
```

`mpi.sbatch`: the image's own check, compiling with `$FC`, `srun` in each MPI
mode across two nodes, `--multi-prog`, and `sbatch` from inside. `minimal-compile.sbatch`:
[the minimal-compile example](../examples/minimal-compile/), unchanged, inside
the container. The image build itself ends with Stage 1's smoke test and the
image's [`lfric-container-check`](rootfs/opt/lfric-env/container/bin/lfric-container-check).

## Limits

- Unprivileged Apptainer maps only your primary group: other groups show as
  `nogroup` inside, and files you create get your primary group. The image's `rsync`
  never sets groups for that reason (Rose installs with `rsync -a`).
- Same-node MPI ranks cannot use cross-memory attach (see MPI above).

- Arm64 only for now; an x86_64 image needs a build off Isambard (e.g. CI).
- Runtime on Isambard 3 is Apptainer; podman-hpc builds the image but the
  helper does not drive it.
- Heterogeneous `srun` steps (`srun ... : ...`) are not supported in the container.
- The SITE section of the helper names Isambard 3's paths; another Cray EX
  needs those edited.
