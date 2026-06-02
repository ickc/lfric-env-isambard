#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-charset-normalizer
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_charset_normalizer() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-charset-normalizer"
  pkg_file="$pkg_dir/package.py"
  if [ -f "$pkg_file" ] && grep -q "charset-normalizer-3.3.2.tar.gz" "$pkg_file"; then
    return 0
  fi
  info "Adding py-charset-normalizer package to simit-spack repo."
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


class PyCharsetNormalizer(PythonPackage):

    """Character encoding auto-detection in Python."""

    pypi = "charset-normalizer/charset-normalizer-3.3.2.tar.gz"

    version(
        "3.3.2",
        sha256="f30c3cb33b24454a82faecaf01b19c18562b1e89558fb6c56de4d9118a032fd5",
    )

    depends_on("python@3:")
    depends_on("py-setuptools", type="build")
EOF
}

patch_simit_py_charset_normalizer
exit $?
