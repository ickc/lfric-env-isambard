#!/usr/bin/env bash
# Auto-generated from install.sh. Target package: vendor/simit-spack .../packages/py-jupyter-server
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_simit_py_jupyter_server() {
  local pkg_dir
  local pkg_file
  if [ -z "$SIMIT_SPACK_DIR" ]; then
    return 0
  fi
  pkg_dir="$SIMIT_SPACK_DIR/repos/metoffice/packages/py-jupyter-server"
  pkg_file="$pkg_dir/package.py"
  if [ -f "$pkg_file" ]; then
    return 0
  fi
  info "Adding py-jupyter-server package to simit-spack repo."
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


class PyJupyterServer(PythonPackage):

    """Jupyter Server backend for web applications like JupyterLab."""

    homepage = "https://github.com/jupyter-server/jupyter_server"
    pypi = "jupyter_server/jupyter_server-2.17.0.tar.gz"

    version(
        "2.17.0",
        sha256="c38ea898566964c888b4772ae1ed58eca84592e88251d2cfc4d171f81f7e99d5",
    )
    version(
        "2.14.2",
        sha256="66095021aa9638ced276c248b1d81862e4c50f292d575920bbe960de1c56b12b",
    )

    depends_on("python@3.9:", type=("build", "run"))
    depends_on("py-hatchling@1.11:", type="build")
    depends_on("py-hatch-jupyter-builder@0.8.1:", type="build")
    depends_on("py-pip", type="build")
    depends_on("py-setuptools", type="build")
    depends_on("py-wheel", type="build")

    with default_args(type=("build", "run")):
        depends_on("py-anyio@3.1.0:")
        depends_on("py-argon2-cffi@21.1:")
        depends_on("py-jinja2@3.0.3:")
        depends_on("py-jupyter-client@7.4.4:")
        depends_on("py-jupyter-core@4.12:")
        depends_on("py-jupyter-events@0.11:")
        depends_on("py-jupyter-server-terminals@0.4.4:")
        depends_on("py-nbconvert@6.4.4:")
        depends_on("py-nbformat@5.3:")
        depends_on("py-overrides@5.0:")
        depends_on("py-packaging@22.0:")
        depends_on("py-prometheus-client@0.9:")
        depends_on("py-pyzmq@24:")
        depends_on("py-send2trash@1.8.2:")
        depends_on("py-terminado@0.8.3:")
        depends_on("py-tornado@6.2:")
        depends_on("py-traitlets@5.6:")
        depends_on("py-websocket-client@1.7:")
EOF
}

patch_simit_py_jupyter_server
exit $?
