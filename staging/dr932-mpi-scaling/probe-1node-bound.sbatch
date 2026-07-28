#!/bin/bash
#SBATCH --job-name=probe-1node-bound
#SBATCH --partition=grace
#SBATCH --nodes=1
#SBATCH --ntasks=108
#SBATCH --cpus-per-task=1
#SBATCH --mem=0
#SBATCH --time=00:20:00
#SBATCH --output=staging/dr932-mpi-scaling/results/1node-bound-%j.out
#
# The cheapest fix available WITHOUT changing MPI stack: keep the UoE MPICH and
# keep Hydra, but pack the job onto one node and pin the ranks
# (`mpiexec -bind-to core -ppn 108`). Compare against probe-1node.out's unbound
# `uoe / mpiexec` row to see what binding alone is worth.
#
#   sbatch staging/dr932-mpi-scaling/probe-1node-bound.sbatch
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

echo "SLURM_JOB_NUM_NODES=${SLURM_JOB_NUM_NODES:-?} NODELIST=${SLURM_JOB_NODELIST:-?}"
echo
timeout 600 bash staging/dr932-mpi-scaling/run-probe.sh uoe mpiexec-bound 108
echo "exit=$?"
