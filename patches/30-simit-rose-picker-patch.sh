#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/rose-picker
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_rose_picker() {
  local pkg_file
  pkg_file="$SIMIT_SPACK_DIR/repos/metoffice/packages/rose-picker/package.py"
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  if [ ! -f "$pkg_file" ]; then
    fail "rose-picker package not found at $pkg_file; cannot patch GitHub URL."
    return 1
  fi
  if ! grep -q "https://github.com/MetOffice/rose_picker.git" "$pkg_file" \
    || grep -q "self.spec.prefix.lib.python" "$pkg_file"; then
    info "Patching rose-picker package definition to use GitHub mirror."
  else
    return 0
  fi
  cat > "$pkg_file" <<'EOF'
# Copyright 2013-2022 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *


class RosePicker(Package):

    """rose_picker - utility for LFRic."""

    homepage = "https://github.com/MetOffice/rose_picker"
    git = "https://github.com/MetOffice/rose_picker.git"

    version("2.0.0", tag="git_migration", preferred=True)

    depends_on("python@3.11:", type=("build", "run"))
    depends_on("py-pip", type="build")

    def install(self, spec, prefix):
        python = spec["python"].command
        python("-m", "pip", "install", "--no-deps", "--prefix", prefix, ".")

    def setup_run_environment(self, env):
        python = self.spec["python"]
        pyver = python.version.up_to(2)
        env.prepend_path(
            "PYTHONPATH",
            join_path(self.spec.prefix, "lib", "python{0}".format(pyver), "site-packages"),
        )
EOF
}

patch_simit_rose_picker
exit $?
