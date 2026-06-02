#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-graphql-core
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_graphql_core() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-graphql-core"
  pkg_file="$pkg_dir/package.py"
  info "Adding py-graphql-core package to simit-spack repo."
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


class PyGraphqlCore(PythonPackage):

    """GraphQL core library."""

    pypi = "graphql-core/graphql_core-3.2.7.tar.gz"

    version(
        "3.2.7",
        sha256="27b6904bdd3b43f2a0556dad5d579bdfdeab1f38e8e8788e555bdcb586a6f62c",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("py-poetry-core", type="build")
    depends_on("py-typing-extensions")
EOF
}

patch_simit_py_graphql_core
exit $?
