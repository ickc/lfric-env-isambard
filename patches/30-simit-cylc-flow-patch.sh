#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/cylc-flow
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_cylc_flow() {
  local pkg_file
  pkg_file="$SIMIT_SPACK_DIR/repos/metoffice/packages/cylc-flow/package.py"
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  if [ ! -f "$pkg_file" ]; then
    fail "cylc-flow package not found at $pkg_file; cannot patch."
    return 1
  fi
  info "Patching cylc-flow package definition to avoid metadata generation failures."
  cat > "$pkg_file" <<'EOF'
# Copyright 2013-2022 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *


class CylcFlow(PythonPackage):

    """Cylc - workflow engine that orchestrates cycling workflows very efficiently.

    Cylc is used in production weather, climate, and environmental
    forecasting on HPC, but is not specialized to those domains.
    """

    homepage = "https://cylc.github.io/"
    pypi = "cylc-flow/cylc_flow-8.6.2.tar.gz"

    version(
        "8.6.2",
        sha256="66d0f4ce8e2fa4ac2f0a29e184ea534a2f4814dd2a116c8d721f11fd6a161f21",
        preferred=True,
    )
    version(
        "8.1.0",
        sha256="19e1e510178d2ea6210bbd5e56dbe30c5066665564b46a6faad134dede831487",
    )
    version(
        "8.0.4",
        sha256="866f39bec037805690ce582a2cb0ccdbf646ea46a4c691c9cb1a1ea13f649a7a",
    )
    version(
        "8.0.1",
        sha256="dfccc1290390f226fe44253bcb0caf65aa175e2f7d165793083feed1f8ea0a7f",
    )
    version(
        "8.0.0",
        sha256="5a4b4bb4e101d65c5c397e6ab810d21b90c8774dca3a9e708de96b22e43d0cfe",
    )
    version(
        "8.0rc2",
        sha256="a8887fcf8f014e2665c9ebbe8a596a71e383e23859fa485860469b7f59fafd2f",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("py-flit-core", type="build")
    depends_on("py-setuptools-scm", type="build")
    depends_on("py-wheel", type="build")
    depends_on("graphviz")
    depends_on("py-ansimarkup")
    depends_on("py-colorama")
    depends_on("py-graphql-core")
    depends_on("py-graphene")
    depends_on("py-jinja2@3.0.3")
    depends_on("py-metomi-isodatetime")
    depends_on("py-packaging")
    depends_on("py-protobuf")
    depends_on("py-psutil")
    depends_on("py-urwid")
    depends_on("py-pyzmq")
EOF
}

patch_simit_cylc_flow
exit $?
