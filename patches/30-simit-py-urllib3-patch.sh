#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-urllib3
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_urllib3() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-urllib3"
  pkg_file="$pkg_dir/package.py"
  if [ -f "$pkg_file" ] && grep -q "py-hatchling" "$pkg_file" && grep -q "py-hatch-vcs" "$pkg_file"; then
    return 0
  fi
  info "Adding py-urllib3 package to simit-spack repo."
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


class PyUrllib3(PythonPackage):

    """HTTP library with thread-safe connection pooling."""

    pypi = "urllib3/urllib3-2.2.3.tar.gz"

    version(
        "2.2.3",
        sha256="e7d814a81dad81e6caf2ec9fdedb284ecc9c73076b62654547cc64ccdcae26e9",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("py-hatchling", type="build")
    depends_on("py-hatch-vcs", type="build")
EOF
}

patch_simit_py_urllib3
exit $?
