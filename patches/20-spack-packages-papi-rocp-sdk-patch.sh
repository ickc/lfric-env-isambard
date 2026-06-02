#!/usr/bin/env bash
# Auto-generated from install.sh. Target: vendor/spack-packages builtin papi (rocp_sdk lambda fix).
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
# No-op at the pinned commit (already fixed upstream); kept as a guard.
PAPI_PKG="$REPO_ROOT/vendor/spack-packages/repos/spack_repo/builtin/packages/papi/package.py"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_papi_rocp_sdk() {
  local pkg="$1"
  if [ -z "$pkg" ] || [ ! -f "$pkg" ]; then
    return 0
  fi
  if grep -q "x in spec.variants and spec.variants\\[x\\].value" "$pkg"; then
    return 0
  fi
  sed -i \
    "s/lambda x: spec\\.variants\\[x\\]\\.value/lambda x: x in spec.variants and spec.variants[x].value/" \
    "$pkg"
}

patch_papi_rocp_sdk "$PAPI_PKG"
exit $?
