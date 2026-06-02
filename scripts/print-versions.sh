#!/usr/bin/env bash
# `pixi run activate` — ensure the environment is active and report tool
# versions. (pixi already auto-activates via scripts/activate.sh before this
# runs; sourcing it again is a harmless idempotent no-op.)
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/activate.sh
. "$_here/activate.sh"

if [ ! -f "$WORKING_DIR/env-runtime.sh" ]; then
  echo "Environment is not built yet."
  echo "  pixi run submodule-init   # one-time: clone submodules"
  echo "  pixi run build            # build the Spack environment"
  exit 1
fi

echo "Spack environment: $ENV_NAME (active)"
echo "rose:     $(rose --version 2>&1)"
echo "cylc:     $(cylc --version 2>&1)"
echo "psyclone: $(psyclone --version 2>&1)"
