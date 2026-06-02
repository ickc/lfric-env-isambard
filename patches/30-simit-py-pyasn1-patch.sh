#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-pyasn1
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_pyasn1() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-pyasn1"
  pkg_file="$pkg_dir/package.py"
  if [ -f "$pkg_file" ]; then
    return 0
  fi
  info "Adding py-pyasn1 package to simit-spack repo."
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


class PyPyasn1(PythonPackage):

    """ASN.1 types and codecs."""

    pypi = "pyasn1/pyasn1-0.6.1.tar.gz"

    version(
        "0.6.1",
        sha256="6f580d2bdd84365380830acf45550f2511469f673cb4a5ae3857a3170128b034",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
EOF
}

patch_simit_py_pyasn1
exit $?
