#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/foxml
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_foxml() {
  local pkg_file
  pkg_file="$SIMIT_SPACK_DIR/repos/metoffice/packages/foxml/package.py"
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  if [ ! -f "$pkg_file" ]; then
    fail "foxml package not found at $pkg_file; cannot patch."
    return 1
  fi
  if grep -q "commit=\"6f60cf178d0776b21406303e91f1e6b42ff0f204\"" "$pkg_file"; then
    return 0
  fi
  info "Patching foxml package definition to use git commit checkout."
  cat > "$pkg_file" <<'EOF'
# Copyright 2013-2022 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *


class Foxml(CMakePackage):

    """FoX - the Fortan/XML library.

    FoX is an XML library written in Fortran 95. It allows software
    developers to read, write and modify XML documents from Fortran
    applications without the complications of dealing with
    multi-language development. FoX can be freely redistributed as
    part of open source and commercial software packages.
    """

    homepage = "https://github.com/andreww/fox"
    git = "https://github.com/andreww/fox.git"

    version(
        "6f60cf1",
        commit="6f60cf178d0776b21406303e91f1e6b42ff0f204",
        preferred=True,
    )
EOF
}

patch_simit_foxml
exit $?
