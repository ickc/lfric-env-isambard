#!/usr/bin/env bash
# `pixi run activate` — ensure the environment is active and report tool
# versions. (pixi already auto-activates via scripts/activate.sh before this
# runs; sourcing it again is a harmless idempotent no-op.)
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/activate.sh
. "$_here/activate.sh"

if [ ! -f "$ENV_RUNTIME" ]; then
  echo "Environment '$LFRIC_STACK' is not built yet."
  echo "  pixi run submodule-init                 # one-time: clone submodules"
  echo "  pixi run build                          # build the cray stack (default)"
  echo "  LFRIC_STACK=spack pixi run build        # build the from-source stack"
  exit 1
fi

echo "Spack environment: $ENV_NAME (active; LFRIC_STACK=$LFRIC_STACK)"
echo "rose:     $(rose --version 2>&1)"
echo "cylc:     $(cylc --version 2>&1)"
echo "psyclone: $(psyclone --version 2>&1)"
