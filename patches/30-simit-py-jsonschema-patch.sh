#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-jsonschema
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_jsonschema() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-jsonschema"
  pkg_file="$pkg_dir/package.py"
  info "Adding py-jsonschema package to simit-spack repo."
  if ! mkdir -p "$pkg_dir"; then
    fail "Unable to create $pkg_dir."
    return 1
  fi
  cat > "$pkg_file" <<'EOF'
# Copyright 2013-2022 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from importlib import import_module

from spack.package import *


jsonschema = import_module("spack_repo.builtin.packages.py_jsonschema.package")


class PyJsonschema(jsonschema.PyJsonschema):

    """An implementation of JSON Schema validation for Python."""

    version(
        "4.17.3",
        sha256="0f864437ab8b6076ba6707453ef8f98a6a0d512a80e93f8abdb676f737ecb60d",
    )
EOF
}

patch_simit_py_jsonschema
exit $?
