#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-pyuv
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_pyuv() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-pyuv"
  pkg_file="$pkg_dir/package.py"
  info "Adding py-pyuv package to simit-spack repo."
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
from llnl.util.filesystem import filter_file


class PyPyuv(PythonPackage):

    """Python interface to libuv."""

    pypi = "pyuv/pyuv-1.4.0.tar.gz"

    version(
        "1.4.0",
        sha256="caea2004d1125fe17cbde3c211c8abc72844e9b8dd7dfa007711e98fbc96fbc2",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("libuv")

    def patch(self):
        filter_file(
            "Py_REFCNT\\(self\\) = refcnt;",
            "Py_SET_REFCNT(self, refcnt);",
            "src/handle.c",
        )
        filter_file(
            "PyUnicode_EncodeUTF8\\(PyUnicode_AS_UNICODE\\(unicode\\), PyUnicode_GET_SIZE\\(unicode\\), \"surrogateescape\"\\);",
            "PyUnicode_AsEncodedString(unicode, \"utf-8\", \"surrogateescape\");",
            "src/common.c",
        )
EOF
}

patch_simit_py_pyuv
exit $?
