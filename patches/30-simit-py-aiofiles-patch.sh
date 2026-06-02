#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-aiofiles
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_aiofiles() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-aiofiles"
  pkg_file="$pkg_dir/package.py"
  if [ -f "$pkg_file" ] && grep -q "py-poetry-core" "$pkg_file"; then
    return 0
  fi
  info "Adding py-aiofiles package to simit-spack repo."
  if ! mkdir -p "$pkg_dir"; then
    fail "Unable to create $pkg_dir."
    return 1
  fi
  cat > "$pkg_file" <<'EOF'
# Copyright 2013-2022 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *


class PyAiofiles(PythonPackage):

    """File support for asyncio."""

    pypi = "aiofiles/aiofiles-0.7.0.tar.gz"

    version(
        "0.7.0",
        sha256="a1c4fc9b2ff81568c83e21392a82f344ea9d23da906e4f6a52662764545e19d4",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("py-poetry-core", type="build")
EOF
}

patch_simit_py_aiofiles
exit $?
