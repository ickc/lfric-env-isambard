#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/metomi-rose
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_metomi_rose() {
  local pkg_file
  pkg_file="$SIMIT_SPACK_DIR/repos/metoffice/packages/metomi-rose/package.py"
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  if [ ! -f "$pkg_file" ]; then
    fail "metomi-rose package not found at $pkg_file; cannot patch."
    return 1
  fi
  info "Patching metomi-rose package definition to include runtime dependencies."
  cat > "$pkg_file" <<'EOF'
# Copyright 2013-2022 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *


class MetomiRose(PythonPackage):

    """Metomi Rose - configuration and workflow suite."""

    homepage = "https://metomi.github.io/rose/"
    pypi = "metomi-rose/metomi_rose-2.5.1.tar.gz"

    version(
        "2.5.1",
        sha256="02fad351f2356b9d2d25432e5d117baf78d4287b0b680cebe5d836f57d6ad2cc",
        preferred=True,
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
    depends_on("py-aiofiles")
    depends_on("py-jinja2")
    depends_on("py-keyring")
    depends_on("py-ldap3")
    depends_on("py-metomi-isodatetime")
    depends_on("py-psutil")
    depends_on("py-requests")
    depends_on("py-sqlalchemy@1:1")
EOF
}

patch_simit_metomi_rose
exit $?
