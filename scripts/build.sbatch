#!/bin/bash
#SBATCH --job-name=lfric-build
#SBATCH --partition=grace
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=12
#SBATCH --time=03:30:00
#SBATCH --output=working_dir/build-%j.out
# Build the LFRic Apps Spack environment on a Grace compute node.
#
#   sbatch scripts/build.sbatch        # from the repo root (cray variant, default)
#   sbatch --export=ALL,LFRIC_STACK=spack scripts/build.sbatch   # from-source variant
#
# The Isambard 3 login nodes cap user processes (ulimit -u ~900), which a full
# parallel Spack build exhausts (fork: Resource temporarily unavailable). The
# build therefore runs on a `grace` compute node. Concretization alone is fine
# on the login node.
#
# Keep the job SMALL and SHORT: the `grace` partition is usually full, so a
# 12-core, non-exclusive, <=3.5 h job backfills into the schedule far sooner
# than a whole-node `--exclusive` reservation — and the build is not CPU-bound
# past ~16 cores (past builds finished in ~50-70 min on 16-32 cores). NOTE: this
# project standardises on --cpus-per-task=12 (so SPACK_JOBS/MAKE_JOBS=12) for its
# builds; raise --cpus-per-task (and resubmit) only if the queue is empty.
#
# Overridable: LFRIC_STACK (cray|spack dependency variant; pass it through Slurm
# with --export=ALL,LFRIC_STACK=spack), SPACK_JOBS (parallel make jobs), PIXI
# (path to the pixi binary).
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}"

export LFRIC_STACK="${LFRIC_STACK:-cray}"
export SPACK_JOBS="${SPACK_JOBS:-${SLURM_CPUS_PER_TASK:-12}}"

PIXI="${PIXI:-$HOME/.local/opt/Linux-aarch64/system/bin/pixi}"
command -v "$PIXI" >/dev/null 2>&1 || PIXI=pixi

echo "host=$(hostname) jobid=${SLURM_JOB_ID:-?} cpus=${SLURM_CPUS_PER_TASK:-?} LFRIC_STACK=$LFRIC_STACK SPACK_JOBS=$SPACK_JOBS pixi=$PIXI"
exec "$PIXI" run build
