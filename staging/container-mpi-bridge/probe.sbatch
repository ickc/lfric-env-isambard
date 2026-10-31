#!/bin/bash
#SBATCH --job-name=mpi-bridge-probe
#SBATCH --partition=grace
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:15:00
#SBATCH --output=mpi-bridge-probe-%j.out
#
# Bare-metal probe: can a binary built against the env's from-source MPICH
# (the stack the container carries) reach Slingshot by swapping host libraries
# in at run time? Run from a directory holding pp_spack, which is
# container/tests/pingpong.f90 compiled with `module load lfric-env/<v>/spack`
# and `$FC -O2 -o pp_spack pingpong.f90`. See README.md for the results.
cd "$SLURM_SUBMIT_DIR"
VIEWLIB=${VIEWLIB:-$PROJECTDIR/lfric-env/Linux-aarch64/v2026.10.08/spack-env/spack/.spack-env/view/lib}
run() { echo; echo "=== $1"; shift; timeout 120 "$@" 2>&1 | grep -vE '^\s*$' | head -25; echo "exit=${PIPESTATUS[0]}"; }
run "own MPICH + own libfabric (tcp), pmi2" env LD_LIBRARY_PATH=$VIEWLIB srun --mpi=pmi2 ./pp_spack
run "own MPICH, pmix" env LD_LIBRARY_PATH=$VIEWLIB srun --mpi=pmix ./pp_spack
run "own MPICH + host libfabric 2.3.1 via LD_LIBRARY_PATH" env LD_LIBRARY_PATH=/opt/cray/libfabric/2.3.1/lib64:$VIEWLIB FI_PROVIDER=cxi MPIR_CVAR_CH4_OFI_CAPABILITY_SETS_DEBUG=1 srun --mpi=pmi2 ./pp_spack
run "own MPICH + host libfabric 2.3.1 via LD_PRELOAD" env LD_LIBRARY_PATH=$VIEWLIB LD_PRELOAD=/opt/cray/libfabric/2.3.1/lib64/libfabric.so.1 srun --mpi=pmi2 ./pp_spack
run "host cray-mpich 9.1.0 via the MPICH ABI (lib-abi-mpich)" env LD_LIBRARY_PATH=/opt/cray/pe/mpich/9.1.0/ofi/gnu/12.3/lib-abi-mpich:/opt/cray/libfabric/2.3.1/lib64:/opt/cray/pe/pmi/default/lib:$VIEWLIB srun ./pp_spack
