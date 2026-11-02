#!/bin/bash
#SBATCH --job-name=lfric-container-atm
#SBATCH --partition=grace
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=24
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=02:00:00
#SBATCH --output=logs/container-lfric-atm-%j.out
#
# The minimal-compile example (examples/minimal-compile/build.sh), unchanged,
# inside the container: compile lfric_atm and run its example. Submit from the
# repo root:
#
#   LFRIC_CONTAINER_IMAGE=/path/to/lfric-env_<version>.sif sbatch --export=ALL container/tests/minimal-compile.sbatch
#
# To the example the container is just another prefix: LFRIC_PREFIX=/opt/lfric-env
# and the spack variant, the one the image holds. Its toolchain comes from the
# container's activation, which is `module load lfric-env/<version>/spack`
# frozen. The build log goes to logs/, because the prefix is read-only here.
# Ends with LFRIC_ATM_OK (from build.sh).
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1
: "${LFRIC_CONTAINER_IMAGE:?set LFRIC_CONTAINER_IMAGE to the image (a .sif)}"
mkdir -p logs
exec container/bin/lfric-container exec env \
  LFRIC_PREFIX=/opt/lfric-env LFRIC_STACK=spack \
  LOCAL_BUILD_LOG="$PWD/logs/container-lfric-atm-${SLURM_JOB_ID:-$$}-make.log" \
  MAKE_JOBS="${SLURM_CPUS_PER_TASK:-24}" \
  bash examples/minimal-compile/build.sh
