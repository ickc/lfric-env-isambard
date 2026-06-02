#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/cylc-uiserver
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_cylc_uiserver() {
  local pkg_file
  pkg_file="$SIMIT_SPACK_DIR/repos/metoffice/packages/cylc-uiserver/package.py"
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  if [ ! -f "$pkg_file" ]; then
    fail "cylc-uiserver package not found at $pkg_file; cannot patch."
    return 1
  fi
  info "Patching cylc-uiserver package definition to include runtime dependencies."
  cat > "$pkg_file" <<'EOF'
# Copyright 2013-2022 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *


class CylcUiserver(PythonPackage):

    """Cylc UI server - provides the Cylc GUI."""

    homepage = "https://cylc.github.io/"
    pypi = "cylc-uiserver/cylc_uiserver-1.8.3.tar.gz"

    version(
        "1.8.3",
        sha256="2f019ac1e6fb78bab612008bc0cc9f2852ce4056d79ef01c46846561b6e7a882",
        preferred=True,
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("cylc-flow@8.6.2:8.6")
    depends_on("py-ansimarkup")
    depends_on("py-graphene")
    depends_on("py-jupyter-server@2.13.0:")
    depends_on("py-packaging")
    depends_on("py-psutil")
    depends_on("py-pyzmq")
    depends_on("py-requests")
    depends_on("py-tornado@6.5:")
    depends_on("py-traitlets@5.2.1:")
EOF
}

patch_simit_cylc_uiserver
exit $?
