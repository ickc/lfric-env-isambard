#!/bin/bash
#SBATCH --job-name=lfric-atm
#SBATCH --partition=grace
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=12
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
# Keep the job SMALL and SHORT so it backfills: 12 cores (this project's
# standard; see build.sbatch), non-exclusive, <=2 h. Build the spack variant with
#   sbatch --export=ALL,LFRIC_STACK=spack scripts/build-lfric-atm.sbatch
# Overridable: LFRIC_STACK (cray|spack), MAKE_JOBS (parallel make jobs), PIXI,
# LFRIC_USE_PIXI (see below).
#
# pixi is OPTIONAL here too. This stage depends only on the Stage-1 environment
# via Lmod, which build-lfric-atm.sh loads itself (it puts the env's Python on
# PATH for local_build.py) — no pixi and no Spack. LFRIC_USE_PIXI=0 runs the
# script directly; no cray-python module is needed (unlike build.sbatch):
#   sbatch --export=ALL,LFRIC_USE_PIXI=0 scripts/build-lfric-atm.sbatch
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

export LFRIC_STACK="${LFRIC_STACK:-cray}"
export MAKE_JOBS="${MAKE_JOBS:-${SLURM_CPUS_PER_TASK:-12}}"

if [ "${LFRIC_USE_PIXI:-1}" = "1" ]; then
  PIXI="${PIXI:-$HOME/.local/opt/Linux-aarch64/system/bin/pixi}"
  command -v "$PIXI" >/dev/null 2>&1 || PIXI=pixi
  echo "host=$(hostname) jobid=${SLURM_JOB_ID:-?} cpus=${SLURM_CPUS_PER_TASK:-?} LFRIC_STACK=$LFRIC_STACK MAKE_JOBS=$MAKE_JOBS pixi=$PIXI"
  exec "$PIXI" run build-lfric-atm
else
  echo "host=$(hostname) jobid=${SLURM_JOB_ID:-?} cpus=${SLURM_CPUS_PER_TASK:-?} LFRIC_STACK=$LFRIC_STACK MAKE_JOBS=$MAKE_JOBS no-pixi (Lmod-only)"
  exec bash scripts/build-lfric-atm.sh
fi
