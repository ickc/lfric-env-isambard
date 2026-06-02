#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-sqlalchemy
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_sqlalchemy() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-sqlalchemy"
  pkg_file="$pkg_dir/package.py"
  info "Adding py-sqlalchemy package to simit-spack repo."
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


class PySqlalchemy(PythonPackage):

    """SQL Toolkit and Object Relational Mapper."""

    pypi = "sqlalchemy/sqlalchemy-1.4.54.tar.gz"

    version(
        "1.4.54",
        sha256="4470fbed088c35dc20b78a39aaf4ae54fe81790c783b3264872a0224f437c31a",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("py-greenlet")
EOF
}

patch_simit_py_sqlalchemy
exit $?
