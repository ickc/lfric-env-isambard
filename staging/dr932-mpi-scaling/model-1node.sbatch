#!/bin/bash
#SBATCH --job-name=dr932-model-1node
#SBATCH --partition=grace
#SBATCH --nodes=1
#SBATCH --ntasks=24
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=00:40:00
#SBATCH --output=staging/dr932-mpi-scaling/results/model-1node-%j.out
#
# The model, packed onto one node -- what examples/science-suites/u-dr932's own
# directives (--nodes=N --ntasks-per-node=M) give you. Memory request is the node's
# true per-core share and is IDENTICAL to model-scatter.sbatch's, so the only thing
# that differs between the two arms is where the ranks land.
#
#   sbatch staging/dr932-mpi-scaling/model-1node.sbatch
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1
bash staging/dr932-mpi-scaling/model-run.sh packed-1node "${STEPS:-300}"
