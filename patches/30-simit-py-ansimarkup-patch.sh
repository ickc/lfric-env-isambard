#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-ansimarkup
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_ansimarkup() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-ansimarkup"
  pkg_file="$pkg_dir/package.py"
  if [ -f "$pkg_file" ]; then
    if grep -q "7b3e3d93fecc5b64d23a6e8eb96dbc8b0b576a211829d948afb397d241a8c51b" "$pkg_file" \
      && grep -q "py-colorama" "$pkg_file"; then
      return 0
    fi
  fi
  info "Adding py-ansimarkup package to simit-spack repo."
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


class PyAnsimarkup(PythonPackage):

    """Convert text into colored ANSI text using markup tags."""

    pypi = "ansimarkup/ansimarkup-2.1.0.tar.gz"

    version(
        "2.1.0",
        sha256="7b3e3d93fecc5b64d23a6e8eb96dbc8b0b576a211829d948afb397d241a8c51b",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("py-hatchling", type="build")
    depends_on("py-colorama")
EOF
}

patch_simit_py_ansimarkup
exit $?
