#!/bin/bash
#SBATCH --job-name=probe-2node
#SBATCH --partition=grace
#SBATCH --nodes=2
#SBATCH --ntasks=108
#SBATCH --ntasks-per-node=54
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=00:30:00
#SBATCH --output=staging/dr932-mpi-scaling/results/2node-%j.out
#
# Control B: force the job across two nodes so every message in the pairwise test
# crosses the interconnect. This is where the UoE stack's MPICH (--with-device=ch3,
# i.e. nemesis/TCP, no libfabric) and cray-mpich (Slingshot cxi, RDMA) separate.
#
#   sbatch staging/dr932-mpi-scaling/probe-2node.sbatch
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

echo "SLURM_JOB_NUM_NODES=${SLURM_JOB_NUM_NODES:-?} NODELIST=${SLURM_JOB_NODELIST:-?}"
echo

for spec in "uoe mpiexec" "cray srun"; do
  set -- $spec
  echo "############ $1 / $2 ############"
  timeout 600 bash staging/dr932-mpi-scaling/run-probe.sh "$1" "$2" 108
  echo "exit=$?"
  echo
done
