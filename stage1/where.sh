#!/usr/bin/env bash
# where.sh — print where this build puts everything, and whether it is built.
# `pixi run where`. Read-only; the fastest way to check what you are about to
# do, or to explain to someone else where their environment came from.
set -uo pipefail
# Re-source the configuration in this process, so an inline override such as
# `LFRIC_STACK=spack bash build.sh` re-derives every path that depends on it.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1
. ./env.sh || exit 1
. ./lib.sh

cat <<EOF
Variant                 $LFRIC_STACK   (LFRIC_STACK)
Version                 $LFRIC_ENV_VERSION   (stage1/VERSION)
Module                  $MODULE_NAME

Stage 1 source          $STAGE1_DIR
Shared per-arch         $LFRIC_BASE
  modulefiles           $MODULEFILES_DIR
  source cache          $LFRIC_SOURCE_CACHE
This version            $LFRIC_PREFIX
  install tree          $LFRIC_PREFIX/opt
  spack env + view      $SPACK_ENV_DIR
Build stage (transient) $LFRIC_WORKING_DIR
EOF

if [ -f "$MODULEFILE" ]; then
  echo "Status                  BUILT ($(date -r "$MODULEFILE" '+%Y-%m-%d %H:%M'))"
  echo ""
  echo "  module use $MODULEFILES_DIR"
  echo "  module load $MODULE_NAME"
else
  echo "Status                  NOT BUILT"
  echo ""
  echo "  cd $STAGE1_DIR && sbatch build.sbatch"
fi
