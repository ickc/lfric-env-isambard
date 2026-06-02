#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/cylc-rose
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_cylc_rose() {
  local pkg_file
  pkg_file="$SIMIT_SPACK_DIR/repos/metoffice/packages/cylc-rose/package.py"
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  if [ ! -f "$pkg_file" ]; then
    fail "cylc-rose package not found at $pkg_file; cannot patch."
    return 1
  fi
  info "Patching cylc-rose package definition to include runtime dependencies."
  cat > "$pkg_file" <<'EOF'
# Copyright 2013-2022 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *


class CylcRose(PythonPackage):

    """Rose plugin for Cylc workflow engine."""

    homepage = "https://cylc.github.io/"
    pypi = "cylc-rose/cylc_rose-1.7.0.tar.gz"

    version(
        "1.7.0",
        sha256="e31a9fb68f30113240126d366f868d2e324d63f0584164085c5e31876b97f75a",
        preferred=True,
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("metomi-rose@2.5:2.5")
    depends_on("cylc-flow@8.6:8.6")
    depends_on("py-metomi-isodatetime")
    depends_on("py-ansimarkup")
    depends_on("py-jinja2")
EOF
}

patch_simit_cylc_rose
exit $?
