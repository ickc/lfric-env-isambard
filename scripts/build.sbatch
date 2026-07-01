#!/bin/bash
#SBATCH --job-name=lfric-build
#SBATCH --partition=grace
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=03:30:00
#SBATCH --output=logs/build-%j.out
#
# Build the LFRic Apps Spack environment (Stage 1) on a Grace compute node.
# Run from the repo root:
#   sbatch scripts/build.sbatch                                 # cray variant (default)
#   sbatch --export=ALL,LFRIC_STACK=spack scripts/build.sbatch  # spack variant
#
# Why a compute node: the login nodes cap user processes (ulimit -u ~900), which a
# full parallel build exhausts. Why these resources: grace allocates memory
# pro-rata (230400 MB / 144 cores = 1600 MB/core), so --mem-per-cpu=1600M claims a
# node's full per-core share and scales with --cpus-per-task; Slurm's default
# (~1 GiB/core) is too little — heavy C++ units (xios, node-js/rust) OOM-kill
# cc1plus under it. A small, short, non-exclusive job backfills sooner. (More in
# MAINTAINER.md.)
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

# ---- Configuration: everything this build needs, set explicitly -----------
export LFRIC_STACK="${LFRIC_STACK:-cray}"                 # cray | spack
# BASE: the per-arch container, shared across env versions (Lustre; survives the
# job). common.sh installs into the VERSIONED prefix $LFRIC_PREFIX/$LFRIC_ENV_VERSION,
# where LFRIC_ENV_VERSION is read from ./VERSION. Set LFRIC_ENV_VERSION to override.
export LFRIC_PREFIX="${LFRIC_PREFIX:-$PROJECTDIR/$USER/opt/$(uname -sm | tr ' ' -)}"
# Transient Spack build stage; node-local NVMe (fast, off the contended Lustre).
# $LOCALDIR is Isambard's per-node local disk; edit if your system differs.
export LFRIC_WORKING_DIR="${LFRIC_WORKING_DIR:-$LOCALDIR/lfric-build-$LFRIC_STACK}"
export SPACK_JOBS="${SPACK_JOBS:-${SLURM_CPUS_PER_TASK:-24}}"
# ---------------------------------------------------------------------------

echo "host=$(hostname) jobid=${SLURM_JOB_ID:-?} cpus=${SLURM_CPUS_PER_TASK:-?} LFRIC_STACK=$LFRIC_STACK"
echo "  LFRIC_ENV_VERSION=${LFRIC_ENV_VERSION:-$(cat VERSION 2>/dev/null || echo '?')}  (install -> \$LFRIC_PREFIX/<version>)"
echo "  LFRIC_PREFIX(base)=$LFRIC_PREFIX"
echo "  LFRIC_WORKING_DIR=$LFRIC_WORKING_DIR"

# Spack 1.0 needs Python in [3.7,3.12); Isambard ships cray-python. (build.sh
# re-checks and fails with a clear hint if it is missing/too new.)
if ! command -v module >/dev/null 2>&1; then
  for f in /opt/cray/pe/lmod/lmod/init/bash /etc/profile.d/lmod.sh /usr/share/lmod/lmod/init/bash; do
    [ -f "$f" ] && . "$f" && break
  done
fi
module load cray-python/3.11.7 || { echo "ERROR: could not load cray-python/3.11.7"; exit 1; }

bash scripts/build.sh

# Prefer pixi? It supplies the Python, so drop the cray-python load and replace the
# line above with:   exec pixi run build      (the LFRIC_* config above still applies)
