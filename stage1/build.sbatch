#!/bin/bash
#SBATCH --job-name=lfric-env
#SBATCH --partition=grace
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=06:00:00
#SBATCH --output=logs/build-%j.out
#
# Build the environment on a Grace compute node. Submit from stage1/:
#
#   sbatch build.sbatch                                 # cray variant (default)
#   sbatch --export=ALL,LFRIC_STACK=spack build.sbatch  # portable variant
#
# Why a compute node: a full build forks thousands of processes; login nodes cap
# you at ~900.
#
# Why --mem-per-cpu=1600M: grace nodes allocate memory pro-rata (230400 MB over
# 144 cores = 1600 MB/core), so this claims exactly the per-core share and
# scales with --cpus-per-task. Slurm's ~1 GiB/core default is not enough — the
# big C++ translation units in xios, node-js and rust OOM-kill cc1plus under it.
#
# Why not exclusive: a small, short, non-exclusive job backfills much sooner,
# and the build is not wide enough to need a whole node.
#
# Why 6 h for a build that takes less: rust and xios are deliberately built at a
# capped -j (see lfric_install), which trades wall-clock for not being OOM-killed.
# Running out of time here is not costly — the install tree persists, so
# resubmitting resumes — but it wastes a scheduling slot, so leave the headroom.
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

export LFRIC_STACK="${LFRIC_STACK:-cray}"
export SPACK_JOBS="${SLURM_CPUS_PER_TASK:-24}"

echo "host=$(hostname)  job=${SLURM_JOB_ID:-?}  cpus=${SLURM_CPUS_PER_TASK:-?}  variant=$LFRIC_STACK"

# pixi supplies the Python that runs Spack and exports the whole configuration
# (env.sh). It also needs no `module load` of its own, which is why the build
# depends on nothing from the login environment except PROJECTDIR and LOCALDIR.
command -v pixi >/dev/null 2>&1 || { echo "ERROR: pixi not on PATH"; exit 1; }
exec pixi run build
