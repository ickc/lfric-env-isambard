#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-psyclone
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_psyclone() {
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_file="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-psyclone/package.py"
  if [ ! -f "$pkg_file" ]; then
    fail "py-psyclone package not found at $pkg_file."
    return 1
  fi
  info "Relaxing py-jsonschema pin in py-psyclone package."
  PKG_FILE="$pkg_file" python3 - <<'PY'
from pathlib import Path
import os

pkg_file = Path(os.environ["PKG_FILE"])
data = pkg_file.read_text()
old = 'depends_on("py-jsonschema@=4.17.3", type=("build", "run"), when="@2.5.0:")'
new = 'depends_on("py-jsonschema@4.17.3:", type=("build", "run"), when="@2.5.0:")'
if old in data:
    pkg_file.write_text(data.replace(old, new))
elif new not in data:
    raise SystemExit(f"Expected dependency not found in {pkg_file}")
PY
}

patch_simit_py_psyclone
exit $?
