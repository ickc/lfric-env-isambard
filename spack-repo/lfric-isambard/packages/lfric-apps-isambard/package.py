# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack.package import *


class LfricAppsIsambard(Package):
    """Bundle of LFRic Apps build/runtime dependencies for Isambard."""

    homepage = "https://github.com/MetOffice/lfric_apps"
    has_code = False

    version("0.1.0")

    # Satisfied by the Cray MPI (cray-mpich) external; see spack.yaml providers.
    depends_on("mpi")
    depends_on("hdf5+fortran+mpi")
    depends_on("netcdf-c+mpi~dap")
    depends_on("netcdf-fortran")
    depends_on("yaxt")
    depends_on("xios@2252")
    depends_on("pfunit+mpi")
    depends_on("shumlib")
    depends_on("blitz")
    depends_on("foxml")
    depends_on("gmake")
    depends_on("pkgconf")
    depends_on("python@3.12+shared")
    depends_on("py-setuptools@:79", type=("build", "run"))
    depends_on("py-fparser")
    depends_on("py-psyclone@3.2.2")
    depends_on("py-jinja2")
    depends_on("py-pyyaml")
    # Spack 1.0 renamed the Met Office Python apps with a py- prefix. rose-picker
    # comes from mo-spack-packages (py-rose-picker); the cylc/rose workflow tools
    # now ship in the Spack builtin repo (py-metomi-rose/py-cylc-flow/...).
    # cylc-uiserver (the Jupyter web GUI) has no Spack 1.0 package in either repo
    # and is not needed for an HPC build/run environment, so it is dropped.
    depends_on("py-rose-picker")
    depends_on("py-metomi-rose")
    depends_on("py-cylc-flow")
    depends_on("py-cylc-rose")
    depends_on("py-ansimarkup")
    depends_on("py-colorama")

    def install(self, spec, prefix):
        mkdirp(prefix)
        touch(join_path(prefix, ".lfric-apps-isambard"))
