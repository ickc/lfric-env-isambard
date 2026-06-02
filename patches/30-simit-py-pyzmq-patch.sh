#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-pyzmq
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_pyzmq() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-pyzmq"
  pkg_file="$pkg_dir/package.py"
  if [ -f "$pkg_file" ]; then
    if grep -q "PYZMQ_USE_BUNDLED" "$pkg_file" && grep -q "depends_on(\"libzmq\")" "$pkg_file"; then
      return 0
    fi
    info "Updating py-pyzmq package definition in simit-spack repo."
  else
    info "Adding py-pyzmq package to simit-spack repo."
  fi
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


class PyPyzmq(PythonPackage):

    """Python bindings for ZeroMQ."""

    pypi = "pyzmq/pyzmq-27.1.0.tar.gz"

    version(
        "27.1.0",
        sha256="ac0765e3d44455adb6ddbf4417dcce460fc40a05978c08efdf2948072f6db540",
    )
    version(
        "24.0.1",
        sha256="216f5d7dbb67166759e59b0479bca82b8acf9bed6015b526b8eb10143fb08e77",
    )
    version(
        "22.3.0",
        sha256="8eddc033e716f8c91c6a2112f0a8ebc5e00532b4a6ae1eb0ccc48e027f9c671c",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("py-cython", type="build")
    depends_on("py-packaging", type="build")
    depends_on("py-scikit-build-core+pyproject", type="build")
    depends_on("libzmq", type=("build", "link"))

    def setup_build_environment(self, env):
        prefix = self.spec["libzmq"].prefix
        env.set("ZMQ_PREFIX", prefix)
        env.set("ZMQ_DIR", prefix)
        env.set("ZMQ_INCLUDE", prefix.include)
        env.set("ZMQ_LIB", prefix.lib)
        env.set("PYZMQ_USE_BUNDLED", "0")
EOF
}

patch_simit_py_pyzmq
exit $?
