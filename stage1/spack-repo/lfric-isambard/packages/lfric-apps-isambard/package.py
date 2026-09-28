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
    depends_on("xios@2701")
    depends_on("pfunit+mpi")
    depends_on("shumlib")
    depends_on("blitz")
    depends_on("foxml")
    depends_on("gmake")
    depends_on("pkgconf")
    depends_on("python@3.12+shared")
    depends_on("py-setuptools@:79", type=("build", "run"))
    depends_on("py-fparser")
    # LFRic 2026.07.1 (apps vn3.2 / core vn3.2) needs PSyclone >= 3.3: its
    # optimisation scripts import OMPParallelTrans from psyclone.psyir.
    # transformations (moved there in 3.3) unguarded — e.g. lfric_atm's
    # meto-ex1a casim_alg_mod.py, which the science-suite examples use.
    # 3.3.1 is what the Met Office runs for this release. mo-spack-packages
    # pulls in py-fparser@0.2.4: and pins py-sympy@1.13.3 for it.
    depends_on("py-psyclone@3.3.1")
    depends_on("py-jinja2")
    depends_on("py-pyyaml")
    # The workflow tools, pinned as a matched set. rose-stem in lfric_apps (since
    # 2025-12, so already at 2026.07.1) needs cylc-flow >= 8.6 for the
    # CYLC_WORKFLOW_SRC_DIR template variable; cylc-rose 1.7 is the plugin
    # release for cylc 8.6, and it needs metomi-rose 2.6-2.7. cylc-uiserver
    # provides `cylc gui`. rose-picker follows the LFRic release tag. The Spack
    # 1.0 builtin repo does not carry all of these versions yet, so
    # spack-repo/lfric-isambard/packages/py-* extend the upstream packages with
    # them.
    depends_on("py-rose-picker@2026.07.1")
    depends_on("py-metomi-rose@2.7.1")
    depends_on("py-cylc-flow@8.6.6")
    depends_on("py-cylc-rose@1.7.2")
    depends_on("py-cylc-uiserver@1.9.4")
    # The checkers lfric_apps' rose-stem runs in its `scripts` group:
    # style_checker (stylist) and fortitude_linter. Both from mo-spack-packages.
    depends_on("py-stylist@0.4.1")
    depends_on("py-fortitude@0.9.0")
    # Also run there: macro_chains_checker imports networkx; python_unit_tests
    # and test_launch-exe run pytest.
    depends_on("py-networkx")
    depends_on("py-pytest")
    depends_on("py-ansimarkup")
    depends_on("py-colorama")

    def install(self, spec, prefix):
        mkdirp(prefix)
        touch(join_path(prefix, ".lfric-apps-isambard"))
