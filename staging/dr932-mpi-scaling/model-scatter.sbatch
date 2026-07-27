#!/bin/bash
#SBATCH --job-name=dr932-model-scatter
#SBATCH --partition=grace
#SBATCH --nodes=12
#SBATCH --ntasks=24
#SBATCH --ntasks-per-node=2
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=00:40:00
#SBATCH --output=staging/dr932-mpi-scaling/results/model-scatter-%j.out
#
# The same model run, scattered thinly over many nodes -- the shape Slurm actually
# handed Denis' job (see README.md: 108 ranks over 4 to 32 nodes, 1-13 ranks each).
# 2 ranks/node x 12 nodes reproduces that density at 24 ranks. Everything else is
# identical to model-1node.sbatch, so the delta is placement alone.
#
#   sbatch staging/dr932-mpi-scaling/model-scatter.sbatch
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1
bash staging/dr932-mpi-scaling/model-run.sh scattered-12node "${STEPS:-300}"
