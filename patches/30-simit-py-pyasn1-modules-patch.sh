#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-pyasn1-modules
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_pyasn1_modules() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-pyasn1-modules"
  pkg_file="$pkg_dir/package.py"
  if [ -f "$pkg_file" ] && grep -q "pyasn1_modules-0.4.1.tar.gz" "$pkg_file"; then
    return 0
  fi
  info "Adding py-pyasn1-modules package to simit-spack repo."
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


class PyPyasn1Modules(PythonPackage):

    """ASN.1 modules for pyasn1."""

    pypi = "pyasn1-modules/pyasn1_modules-0.4.1.tar.gz"

    version(
        "0.4.1",
        sha256="c28e2dbf9c06ad61c71a075c7e0f9fd0f1b0bb2d2ad4377f240d33ac2ab60a7c",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("py-pyasn1")
EOF
}

patch_simit_py_pyasn1_modules
exit $?
