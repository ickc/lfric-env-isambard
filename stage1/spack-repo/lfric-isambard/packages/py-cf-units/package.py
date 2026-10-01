# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

# Replaces the builtin py-cf-units, which stops at 2.1.4; Iris 3.16 needs
# cf-units >= 3.1. Written out rather than subclassed: 3.x changed the build
# (setuptools-scm, Cython 3) and dropped the builtin's unconditional six, antlr4
# runtime and pytest-runner dependencies, which a subclass cannot remove. Drop
# this once builtin carries 3.x.
from spack_repo.builtin.build_systems.python import PythonPackage

from spack.package import *


class PyCfUnits(PythonPackage):
    """Units of measure as required by the Climate and Forecast (CF)
    metadata conventions.
    """

    homepage = "https://github.com/SciTools/cf-units"
    pypi = "cf-units/cf_units-3.3.1.tar.gz"

    license("BSD-3-Clause")

    version("3.3.1", sha256="84339f582994ae32ca5c472075c1e603a89f6c6f5a96cc1031bb5da700a14f3a")

    depends_on("c", type="build")

    depends_on("python@3.11:", type=("build", "link", "run"))
    with default_args(type="build"):
        depends_on("py-setuptools@77.0.3:")
        depends_on("py-setuptools-scm@8:")
        depends_on("py-cython@3:")
    depends_on("py-numpy", type=("build", "link", "run"))
    with default_args(type=("build", "run")):
        depends_on("py-cftime@1.2:")
        depends_on("py-jinja2")
    depends_on("udunits")

    def setup_build_environment(self, env):
        udunits = self.spec["udunits"].prefix
        env.set("UDUNITS2_INCDIR", udunits.include)
        env.set("UDUNITS2_LIBDIR", udunits.lib)
        # Bundles udunits' XML unit database into the package (cf_units/etc/share),
        # so cf-units finds it from any prefix, view or not.
        env.set("UDUNITS2_XML_PATH", join_path(udunits.share, "udunits", "udunits2.xml"))
