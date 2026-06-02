#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-metomi-isodatetime
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_metomi_isodatetime() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-metomi-isodatetime"
  pkg_file="$pkg_dir/package.py"
  if [ -f "$pkg_file" ]; then
    return 0
  fi
  info "Adding py-metomi-isodatetime package to simit-spack repo."
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


class PyMetomiIsodatetime(PythonPackage):

    """Metomi date/time library providing ISO 8601 support."""

    version(
        "3.1.0",
        url="https://files.pythonhosted.org/packages/00/cc/e910e3e8616807dfb9a526e2887623398fee67c987a2112aee103bd120f5/metomi-isodatetime-1!3.1.0.tar.gz",
        sha256="2ec15eb9c323d5debd0678f33af99bc9a91aa0b534ee5f65f3487aed518ebf2d",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
EOF
}

patch_simit_py_metomi_isodatetime
exit $?
