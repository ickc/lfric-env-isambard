#!/bin/bash
#SBATCH --job-name=lfric-atm
#SBATCH --account=brics.e5a
#SBATCH --partition=grace
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --time=02:00:00
#SBATCH --output=working_dir/lfric-atm-%j.out
# Compile lfric_atm (and run its example) on a Grace compute node.
#
#   sbatch scripts/build-lfric-atm.sbatch        # from the repo root
#
# Prerequisites: `pixi run build` has produced the Spack environment, and
# `pixi run submodule-init` has populated the pinned physics submodules under
# vendor/physics/ (casim/jules/socrates/ukca). The compile reads those via
# PHYSICS_ROOT and needs no network/SSH (handy on network-restricted nodes).
#
# Keep the job SMALL and SHORT so it backfills: 16 cores, non-exclusive, <=2 h.
# Overridable: MAKE_JOBS (parallel make jobs), PIXI (path to the pixi binary).
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

export MAKE_JOBS="${MAKE_JOBS:-${SLURM_CPUS_PER_TASK:-16}}"

PIXI="${PIXI:-$HOME/.local/opt/Linux-aarch64/system/bin/pixi}"
command -v "$PIXI" >/dev/null 2>&1 || PIXI=pixi

echo "host=$(hostname) jobid=${SLURM_JOB_ID:-?} cpus=${SLURM_CPUS_PER_TASK:-?} MAKE_JOBS=$MAKE_JOBS pixi=$PIXI"
exec "$PIXI" run build-lfric-atm
