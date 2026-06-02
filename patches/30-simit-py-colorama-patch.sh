#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-colorama
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_colorama() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-colorama"
  pkg_file="$pkg_dir/package.py"
  if [ -f "$pkg_file" ]; then
    return 0
  fi
  info "Adding py-colorama package to simit-spack repo."
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


class PyColorama(PythonPackage):

    """Cross-platform colored terminal text."""

    pypi = "colorama/colorama-0.4.6.tar.gz"

    version(
        "0.4.6",
        sha256="08695f5cb7ed6e0531a20572697297273c47b8cae5a63ffc6d6ed5c201be6e44",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("py-hatchling", type="build")
EOF
}

patch_simit_py_colorama
exit $?
