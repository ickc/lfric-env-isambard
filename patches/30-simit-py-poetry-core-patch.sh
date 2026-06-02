#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-poetry-core
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_poetry_core() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-poetry-core"
  pkg_file="$pkg_dir/package.py"
  if [ -f "$pkg_file" ] && grep -q 'version("2.3.0"' "$pkg_file"; then
    return 0
  fi
  info "Ensuring py-poetry-core package is updated in simit-spack repo."
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


class PyPoetryCore(PythonPackage):

    """PEP 517 build backend for Poetry."""

    pypi = "poetry-core/poetry_core-2.3.0.tar.gz"

    version(
        "2.3.0",
        sha256="f6da8f021fe380d8c9716085f4dcc5d26a5120a2452e077196333892af5de307",
    )

    depends_on("python@3.10:")
    depends_on("py-setuptools", type="build")
EOF
}

patch_simit_py_poetry_core
exit $?
