#!/usr/bin/env bash
# `pixi run activate` — ensure the environment is active and report tool
# versions. (pixi already auto-activates via common.sh + activate.sh before this
# runs; sourcing them again is a harmless idempotent no-op.)
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# common.sh sets MODULEPATH/MODULE_NAME/MODULEFILE etc.; activate.sh module-loads.
# shellcheck source=scripts/common.sh
. "$_here/common.sh"
# shellcheck source=scripts/activate.sh
. "$_here/activate.sh"

if [ ! -f "$MODULEFILE" ]; then
  echo "Environment '$LFRIC_STACK' is not built yet (no modulefile at $MODULEFILE)."
  echo "  Build it on a compute node (from the repo root):"
  echo "    sbatch scripts/build.sbatch                                 # cray (default)"
  echo "    sbatch --export=ALL,LFRIC_STACK=spack scripts/build.sbatch  # spack"
  echo "  (with pixi: pixi run build / pixi run build-spack)"
  exit 1
fi

echo "Spack environment: $ENV_NAME (active; LFRIC_STACK=$LFRIC_STACK)"
echo "  via Lmod: module use $MODULEFILES_DIR && module load $MODULE_NAME"
echo "rose:     $(rose --version 2>&1)"
echo "cylc:     $(cylc --version 2>&1)"
echo "psyclone: $(psyclone --version 2>&1)"
