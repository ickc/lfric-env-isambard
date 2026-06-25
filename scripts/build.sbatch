#!/bin/bash
#SBATCH --job-name=lfric-build
#SBATCH --partition=grace
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=03:30:00
#SBATCH --output=logs/build-%j.out
# Memory on grace is PRO-RATA to cores: RealMemory 230400 MB / 144 cores =
# 1600 MB/core (probe with `scontrol show node <grace-node>`). --mem-per-cpu=1600M
# therefore claims a node's full per-core share and scales automatically with
# --cpus-per-task — no over-request (a flat --mem far above core-share inflates the
# job's footprint and delays scheduling under CR_CORE_MEMORY). Slurm's DEFAULT
# (~1 GiB/core) is too little: heavy C++ TUs (xios' group_template_decl, node-js/
# rust LLVM/V8) OOM-kill cc1plus ("Killed signal terminated program cc1plus") under
# it. We use 24 cores => 37.5 GiB total — ample headroom over the 12-core/12 GiB
# job that OOM'd, and faster. Bumping --cpus-per-task raises memory in lockstep.
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
# 24-core, non-exclusive, <=3.5 h job backfills into the schedule far sooner than
# a whole-node `--exclusive` reservation — and the build is not CPU-bound past
# ~16-24 cores (past builds finished in ~50-70 min on 16-32 cores). This project
# uses --cpus-per-task=24 (so SPACK_JOBS/MAKE_JOBS=24); the memory request scales
# with it via --mem-per-cpu (see the directives above) — 24 cores gives compiles
# enough RAM to avoid the cc1plus OOM a 12-core/12 GiB job hit on xios.
#
# Overridable: LFRIC_STACK (cray|spack dependency variant; pass it through Slurm
# with --export=ALL,LFRIC_STACK=spack), SPACK_JOBS (parallel make jobs), PIXI
# (path to the pixi binary), LFRIC_USE_PIXI (see below).
#
# pixi is OPTIONAL. LFRIC_USE_PIXI=1 (default) drives the build through pixi;
# LFRIC_USE_PIXI=0 takes the no-pixi path — load a Spack-suitable Python (Isambard
# ships cray-python/3.11.7; override with CRAY_PYTHON_MODULE) and run the build
# script directly. Either way scripts/build.sh does the real work.
#   sbatch --export=ALL,LFRIC_USE_PIXI=0 scripts/build.sbatch        # no-pixi, cray
#   sbatch --export=ALL,LFRIC_USE_PIXI=0,LFRIC_STACK=spack scripts/build.sbatch
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

export LFRIC_STACK="${LFRIC_STACK:-cray}"
export SPACK_JOBS="${SPACK_JOBS:-${SLURM_CPUS_PER_TASK:-12}}"

if [ "${LFRIC_USE_PIXI:-1}" = "1" ]; then
  PIXI="${PIXI:-pixi}"
  command -v "$PIXI" >/dev/null 2>&1 || {
    echo "ERROR: pixi not found (looked for '$PIXI' on PATH). Install it" >&2
    echo "       (https://pixi.sh) and put it on PATH, set PIXI=/path/to/pixi," >&2
    echo "       or take the no-pixi path: --export=ALL,LFRIC_USE_PIXI=0." >&2
    exit 1; }
  echo "host=$(hostname) jobid=${SLURM_JOB_ID:-?} cpus=${SLURM_CPUS_PER_TASK:-?} LFRIC_STACK=$LFRIC_STACK SPACK_JOBS=$SPACK_JOBS pixi=$PIXI"
  exec "$PIXI" run build
else
  # No-pixi: bring a Spack-suitable Python ourselves. build.sh's preflight rejects
  # anything outside [3.7,3.12). SPACK_PYTHON is captured from python3 by common.sh.
  CRAY_PYTHON_MODULE="${CRAY_PYTHON_MODULE:-cray-python/3.11.7}"
  if ! command -v module >/dev/null 2>&1; then
    for f in /opt/cray/pe/lmod/lmod/init/bash /etc/profile.d/lmod.sh \
             /usr/share/lmod/lmod/init/bash; do
      # shellcheck source=/dev/null
      [ -f "$f" ] && . "$f" && break
    done
  fi
  module load "$CRAY_PYTHON_MODULE" \
    || { echo "ERROR: could not 'module load $CRAY_PYTHON_MODULE' (Spack needs Python <3.12)"; exit 1; }
  echo "host=$(hostname) jobid=${SLURM_JOB_ID:-?} cpus=${SLURM_CPUS_PER_TASK:-?} LFRIC_STACK=$LFRIC_STACK SPACK_JOBS=$SPACK_JOBS no-pixi python=$(command -v python3)"
  exec bash scripts/build.sh
fi
