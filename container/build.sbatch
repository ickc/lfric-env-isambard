#!/bin/bash
#SBATCH --job-name=lfric-container
#SBATCH --partition=grace
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=72
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=12:00:00
#SBATCH --output=logs/container-build-%j.out
#
# Build the LFRic environment image on a Grace compute node. Submit from the
# repo root:
#
#   sbatch container/build.sbatch                          # build + SIF
#   sbatch --export=ALL,PUSH=1 container/build.sbatch      # ... and push
#
# Everything else is container/build.sh's environment (LFRIC_CONTAINER_BASE,
# LFRIC_CONTAINER_REPO, ...), passed through with --export=ALL.
#
# Why a compute node: inside the image build is Stage 1's full Spack build,
# which forks far more processes than a login node allows (stage1/build.sbatch).
# Why 72 cores and 12 h: on top of Stage 1's spack variant (rust, node-js, xios
# built at a capped -j; see stage1/lib.sh) the image builds gcc itself, pushes
# every package to the binary cache, and squashes a multi-GB SIF. A rebuild with
# a warm cache takes a fraction of that. --mem-per-cpu as stage1/build.sbatch.
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1
mkdir -p logs
export SPACK_JOBS="${SPACK_JOBS:-${SLURM_CPUS_PER_TASK:-16}}"
echo "host=$(hostname)  job=${SLURM_JOB_ID:-?}  cpus=${SLURM_CPUS_PER_TASK:-?}"
exec bash container/build.sh
