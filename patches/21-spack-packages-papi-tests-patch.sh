#!/usr/bin/env bash
# Auto-generated from install.sh. Target: vendor/spack-packages builtin papi (--with-tests normalise).
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
# No-op at the pinned commit (uses --with-tests=ctests/=); kept as a guard.
PAPI_PKG="$REPO_ROOT/vendor/spack-packages/repos/spack_repo/builtin/packages/papi/package.py"
if [ -f "$PAPI_PKG" ] && grep -q "with-tests=" "$PAPI_PKG"; then
  sed -i "s/--with-tests=no/--with-tests=/" "$PAPI_PKG" && echo "INFO: papi --with-tests normalised"
fi
