#!/bin/bash
#SBATCH --job-name=lfric-atm
#SBATCH --partition=grace
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=02:00:00
#SBATCH --output=logs/lfric-atm-%j.out
#
# MINIMAL-COMPILE EXAMPLE: compile lfric_atm (and run its example) on a Grace compute node.
# Submit from the repo root:
#   sbatch examples/minimal-compile/build.sbatch                                # cray (default)
#   sbatch --export=ALL,LFRIC_STACK=spack examples/minimal-compile/build.sbatch # spack
#
# Prerequisites: Stage 1 is built for this variant (scripts/build.sbatch) and the
# physics submodules are initialised (see README). build.sh loads the env via
# Lmod itself (it also puts the env's Python on PATH for local_build.py), so no
# cray-python module is needed here. Resource rationale: see scripts/build.sbatch.
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

# ---- Configuration --------------------------------------------------------
export LFRIC_STACK="${LFRIC_STACK:-cray}"                 # cray | spack (must be built)
# BASE that Stage 1 installed into; the env it loads is the VERSIONED prefix
# $LFRIC_PREFIX/$LFRIC_ENV_VERSION (LFRIC_ENV_VERSION read from ./VERSION). It MUST
# match the version Stage 1 built — both default to ./VERSION, so they agree.
export LFRIC_PREFIX="${LFRIC_PREFIX:-$PROJECTDIR/$USER/opt/$(uname -sm | tr ' ' -)}"
export MAKE_JOBS="${MAKE_JOBS:-${SLURM_CPUS_PER_TASK:-24}}"
# ---------------------------------------------------------------------------

echo "host=$(hostname) jobid=${SLURM_JOB_ID:-?} cpus=${SLURM_CPUS_PER_TASK:-?} LFRIC_STACK=$LFRIC_STACK MAKE_JOBS=$MAKE_JOBS"
echo "  LFRIC_ENV_VERSION=${LFRIC_ENV_VERSION:-$(cat VERSION 2>/dev/null || echo '?')}  (env -> \$LFRIC_PREFIX/<version>)"
echo "  LFRIC_PREFIX(base)=$LFRIC_PREFIX"

bash examples/minimal-compile/build.sh

# Prefer pixi? Replace the line above with:  exec pixi run build-lfric-atm
